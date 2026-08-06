import Foundation

struct MediaItem {
    var source: URL
    var filename: String
    var ext: String
    var kind: MediaKind
    var size: Int64
    var date: ResolvedDate
    /// Destination relative to the destination root, e.g. "2026-06-15/Photos/DSCF6810.RAF"
    var relativeDestination: String
}

struct ScanResult {
    var items: [MediaItem] = []
    var skippedJunk = 0
    var skippedByFilter = 0
    /// Extensions seen that matched neither the photo nor the video tables.
    var unknownExtensions: [String: Int] = [:]
    var unreadable: [(URL, String)] = []

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    var days: [String] { Array(Set(items.map { $0.date.day })).sorted() }
    var photoCount: Int { items.filter { $0.kind == .photo }.count }
    var videoCount: Int { items.filter { $0.kind == .video }.count }
    var otherCount: Int { items.filter { $0.kind == .other }.count }
}

struct Scanner {
    let options: Options
    let resolver: DateResolver

    func scan(card: Card) -> ScanResult {
        var result = ScanResult()
        let fm = FileManager.default

        guard let walker = fm.enumerator(
            at: card.dcimURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [],
            errorHandler: { url, err in
                result.unreadable.append((url, err.localizedDescription))
                return true  // keep going; one bad folder must not abort the import
            }
        ) else { return result }

        while let url = walker.nextObject() as? URL {
            let name = url.lastPathComponent

            // Prune camera-internal and OS bookkeeping directories entirely.
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if Formats.ignoredDirectories.contains(name.uppercased()) || name.hasPrefix(".") {
                    walker.skipDescendants()
                }
                continue
            }

            if Formats.isJunk(name) {
                result.skippedJunk += 1
                continue
            }

            let ext = url.pathExtension
            var kind = Formats.kind(forExtension: ext)

            // A sidecar inherits the bucket of the media file it belongs to.
            if kind == .other, Formats.isSidecar(ext) {
                kind = siblingKind(of: url) ?? .other
            }

            if kind == .other {
                result.unknownExtensions[ext.isEmpty ? "(none)" : ext.uppercased(), default: 0] += 1
                if !options.includeOther {
                    result.skippedByFilter += 1
                    continue
                }
            }

            if let only = options.onlyKind, only != kind {
                result.skippedByFilter += 1
                continue
            }

            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else {
                result.unreadable.append((url, "could not read attributes"))
                continue
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

            let date = resolver.resolve(url: url, kind: kind, attributes: attrs)

            if let since = options.since, let inst = date.instant, inst < since {
                result.skippedByFilter += 1
                continue
            }
            if let until = options.until, let inst = date.instant, inst > until {
                result.skippedByFilter += 1
                continue
            }

            let rel = destinationPath(day: date.day, kind: kind, filename: name)

            result.items.append(MediaItem(
                source: url,
                filename: name,
                ext: ext.uppercased(),
                kind: kind,
                size: size,
                date: date,
                relativeDestination: rel
            ))
        }

        // Stable order: day, then kind, then filename — makes runs reproducible
        // and keeps a shoot's frames sequential in the progress output.
        result.items.sort {
            if $0.date.day != $1.date.day { return $0.date.day < $1.date.day }
            if $0.kind != $1.kind { return $0.kind == .photo }
            return $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
        return result
    }

    /// For `DSCF6810.XMP`, look for `DSCF6810.RAF` / `.JPG` / `.MOV` next to it.
    private func siblingKind(of url: URL) -> MediaKind? {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        for f in files where !Formats.isJunk(f) {
            guard (f as NSString).deletingPathExtension == base, f != url.lastPathComponent
            else { continue }
            let k = Formats.kind(forExtension: (f as NSString).pathExtension)
            if k != .other { return k }
        }
        return nil
    }

    private func destinationPath(day: String, kind: MediaKind, filename: String) -> String {
        if options.flat { return "\(day)/\(filename)" }
        let bucket: String
        switch kind {
        case .photo: bucket = options.photosDirName
        case .video: bucket = options.videosDirName
        case .other: bucket = options.otherDirName
        }
        return "\(day)/\(bucket)/\(filename)"
    }
}
