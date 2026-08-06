import Foundation

struct Card {
    var volumeURL: URL          // e.g. /Volumes/Untitled  (or the folder given via --source)
    var dcimURL: URL            // the DCIM directory we will walk
    var name: String
    var isRemovable: Bool
    var isFujifilm: Bool        // strong Fujifilm signature found
    var totalCapacity: Int64
    var availableCapacity: Int64

    var displayName: String {
        isFujifilm ? "\(name) (Fujifilm)" : name
    }
}

enum Volumes {

    /// Find every mounted removable volume that looks like a camera card.
    ///
    /// Note on `volumeIsInternal`: a MacBook's built-in SD slot reports the card
    /// as **internal** (`diskutil` shows "Device Location: Internal"), so
    /// filtering on that key would miss the very case this tool exists for.
    /// Removable/ejectable are the keys that actually discriminate.
    static func detectCards() -> [Card] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeIsBrowsableKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeURLKey,
        ]
        let fm = FileManager.default
        guard let mounted = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var cards: [Card] = []
        for url in mounted {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let removable = (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false)
            guard removable else { continue }
            guard let dcim = findDCIM(in: url) else { continue }

            cards.append(Card(
                volumeURL: url,
                dcimURL: dcim,
                name: v.volumeName ?? url.lastPathComponent,
                isRemovable: true,
                isFujifilm: hasFujifilmSignature(volume: url, dcim: dcim),
                totalCapacity: Int64(v.volumeTotalCapacity ?? 0),
                availableCapacity: Int64(v.volumeAvailableCapacity ?? 0)
            ))
        }
        // Fujifilm cards first, then alphabetical — deterministic ordering.
        return cards.sorted {
            $0.isFujifilm != $1.isFujifilm ? $0.isFujifilm : $0.name < $1.name
        }
    }

    /// Build a Card from an explicit --source path. Accepts a volume root, a
    /// DCIM folder, or any folder containing media (e.g. an already-offloaded
    /// backup you want re-sorted).
    static func card(forPath path: String) -> Card? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        // Walk into DCIM if it's there; otherwise treat the folder itself as the tree.
        let dcim = findDCIM(in: url) ?? url

        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeURLKey,
        ]
        let v = try? url.resourceValues(forKeys: Set(keys))
        let volRoot = v?.volume ?? url

        return Card(
            volumeURL: url,
            dcimURL: dcim,
            name: url.lastPathComponent.isEmpty
                ? (v?.volumeName ?? url.path)
                : url.lastPathComponent,
            isRemovable: (v?.volumeIsRemovable ?? false) || (v?.volumeIsEjectable ?? false),
            isFujifilm: hasFujifilmSignature(volume: volRoot, dcim: dcim),
            totalCapacity: Int64(v?.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(v?.volumeAvailableCapacity ?? 0)
        )
    }

    private static func findDCIM(in root: URL) -> URL? {
        let fm = FileManager.default
        // Case can vary across cameras/filesystems; check the common spellings.
        for name in ["DCIM", "dcim", "Dcim"] {
            let c = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: c.path, isDirectory: &isDir), isDir.boolValue {
                return c
            }
        }
        return nil
    }

    /// Look for markers only a Fujifilm body leaves behind.
    ///  - `FFDB/` at the volume root (the camera's image database)
    ///  - a `DCIM/###_FUJI` numbered folder
    ///  - `DSCF####.RAF` files
    private static func hasFujifilmSignature(volume: URL, dcim: URL) -> Bool {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: volume.appendingPathComponent("FFDB").path, isDirectory: &isDir),
           isDir.boolValue { return true }

        guard let subdirs = try? fm.contentsOfDirectory(atPath: dcim.path) else { return false }
        for d in subdirs {
            // 100_FUJI, 101_FUJI, ... and the FinePix-era 100_FUJI/100FUJI spellings.
            if d.uppercased().contains("FUJI") { return true }
        }

        // Fall back to sniffing filenames one level down.
        for d in subdirs.prefix(8) {
            let sub = dcim.appendingPathComponent(d)
            guard let files = try? fm.contentsOfDirectory(atPath: sub.path) else { continue }
            for f in files.prefix(40) where !Formats.isJunk(f) {
                let u = f.uppercased()
                if u.hasPrefix("DSCF") || u.hasSuffix(".RAF") { return true }
            }
        }
        return false
    }

    /// Ask the system to eject. Uses `diskutil`, which handles the unmount +
    /// power-down handshake correctly for card readers.
    @discardableResult
    static func eject(_ card: Card) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["eject", card.volumeURL.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
