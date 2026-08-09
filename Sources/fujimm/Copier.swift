import Foundation
import CryptoKit

/// Set from the SIGINT/SIGTERM handler. Only `sig_atomic_t` writes are legal in
/// a signal handler, so the actual cleanup happens in the copy loop.
nonisolated(unsafe) var gInterrupted: sig_atomic_t = 0

enum CopyOutcome {
    case copied(bytes: Int64)
    case skippedIdentical
    case renamed(to: String)
    case overwritten(bytes: Int64)
    case failed(String)
    case wouldCopy          // --dry-run
    case interrupted
}

struct CopyRecord {
    var item: MediaItem
    var outcome: CopyOutcome
    var destination: URL
}

final class Copier {
    private let options: Options
    private let bufferSize = 4 * 1024 * 1024   // 4 MB — good match for SD reader throughput

    init(options: Options) { self.options = options }

    static func installSignalHandlers() {
        signal(SIGINT)  { _ in gInterrupted = 1 }
        signal(SIGTERM) { _ in gInterrupted = 1 }
    }

    var interrupted: Bool { gInterrupted != 0 }

    /// Copy one item. Never touches the source beyond opening it read-only.
    func copy(_ item: MediaItem,
              toRoot root: URL,
              progress: (Int64) -> Void) -> CopyRecord {

        var dest = root.appendingPathComponent(item.relativeDestination)
        let fm = FileManager.default

        var didOverwrite = false
        var didRename = false

        // Where this file goes. Decided once, before the dry-run branch, so a
        // dry run cannot predict something the real run will not do.
        if options.overwrite {
            if fm.fileExists(atPath: dest.path) {
                // Replacing a file with itself is pointless I/O, so an identical
                // copy is still skipped even when --overwrite was asked for.
                if identity(of: item, matches: dest) == .identical {
                    return CopyRecord(item: item, outcome: .skippedIdentical, destination: dest)
                }
                didOverwrite = true
            }
        } else {
            switch placement(of: item, at: dest) {
            case .existing(let url):
                return CopyRecord(item: item, outcome: .skippedIdentical, destination: url)
            case .fresh(let url):
                didRename = url != dest
                dest = url
            case .exhausted:
                return CopyRecord(
                    item: item,
                    outcome: .failed("\(item.filename): all 9999 -N name slots are taken"),
                    destination: dest
                )
            }
        }

        if options.dryRun {
            if didRename {
                return CopyRecord(item: item, outcome: .renamed(to: dest.lastPathComponent),
                                  destination: dest)
            }
            return CopyRecord(item: item, outcome: .wouldCopy, destination: dest)
        }

        // Last line of defence before anything is written. The flags that compose
        // this path are validated at parse time, but this catches whatever a
        // future flag introduces, and it is the only check that sees the fully
        // composed path.
        guard PathSafety.isContained(dest.path, in: root.path) else {
            return CopyRecord(
                item: item,
                outcome: .failed("refusing to write outside \(root.path)"),
                destination: dest
            )
        }

        // Not FileManager.createDirectory(withIntermediateDirectories:): that
        // follows a symlink, so one planted inside the destination sends the
        // write outside it — after containment has already passed.
        guard PathSafety.createDirectoryChain(at: dest.deletingLastPathComponent().path) else {
            return CopyRecord(item: item,
                              outcome: .failed("cannot create folder for \(item.filename)"),
                              destination: dest)
        }

        // Write to a sibling temp file and rename into place, so an interrupted
        // run can never leave a truncated file wearing the real name.
        //
        // The name derives from the *source* filename, not from `dest`, so two
        // sources colliding into one directory share a temp path. That is safe
        // only because this loop is serial and the first temp is renamed away
        // before the second starts. Putting N files in flight (imp-copy-overlap)
        // makes it a live corruption bug — key the name on `dest` first.
        let temp = dest.deletingLastPathComponent()
            .appendingPathComponent(".fujimm-\(ProcessInfo.processInfo.processIdentifier)-\(item.filename).part")

        let result = streamCopy(from: item.source, to: temp, progress: progress)

        switch result {
        case .failure(let message):
            try? fm.removeItem(at: temp)
            return CopyRecord(item: item, outcome: .failed(message), destination: dest)

        case .cancelled:
            try? fm.removeItem(at: temp)
            return CopyRecord(item: item, outcome: .interrupted, destination: dest)

        case .success(let bytes, let digest):
            if options.verify {
                guard let sourceDigest = digest else {
                    try? fm.removeItem(at: temp)
                    return CopyRecord(item: item, outcome: .failed("could not hash source"),
                                      destination: dest)
                }
                guard let written = sha256(of: temp) else {
                    try? fm.removeItem(at: temp)
                    return CopyRecord(item: item, outcome: .failed("could not hash copy"),
                                      destination: dest)
                }
                guard written == sourceDigest else {
                    try? fm.removeItem(at: temp)
                    return CopyRecord(item: item,
                                      outcome: .failed("checksum mismatch — copy discarded"),
                                      destination: dest)
                }
            }

            // Carry the camera's timestamps onto the copy so the sorted tree
            // still sorts by capture time in Finder.
            //
            // The modification time comes from `item`, not from a fresh stat of
            // the source: Scanner already resolved it through any symlink, and
            // re-stat'ing here with attributesOfItem would not. It also makes
            // `identity(of:matches:)` sound by construction — a copy this tool
            // wrote always carries exactly the mtime it will later compare.
            var keep: [FileAttributeKey: Any] = [.modificationDate: item.mtime]
            if let attrs = try? fm.attributesOfItem(
                atPath: item.source.resolvingSymlinksInPath().path
            ), let created = attrs[.creationDate] {
                keep[.creationDate] = created
            }
            try? fm.setAttributes(keep, ofItemAtPath: temp.path)

            do {
                if didOverwrite && fm.fileExists(atPath: dest.path) {
                    _ = try fm.replaceItemAt(dest, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: dest)
                }
            } catch {
                try? fm.removeItem(at: temp)
                return CopyRecord(item: item,
                                  outcome: .failed("cannot finalise: \(error.localizedDescription)"),
                                  destination: dest)
            }

            if didOverwrite { return CopyRecord(item: item, outcome: .overwritten(bytes: bytes), destination: dest) }
            if didRename { return CopyRecord(item: item, outcome: .renamed(to: dest.lastPathComponent), destination: dest) }
            return CopyRecord(item: item, outcome: .copied(bytes: bytes), destination: dest)
        }
    }

    // MARK: - Streaming copy

    private enum StreamResult {
        case success(bytes: Int64, digest: String?)
        case failure(String)
        case cancelled
    }

    private func streamCopy(from src: URL, to dst: URL,
                            progress: (Int64) -> Void) -> StreamResult {
        // O_RDONLY: the source is opened read-only, full stop. This tool has no
        // code path that writes to, truncates, moves or unlinks a source file.
        let inFD = open(src.path, O_RDONLY)
        guard inFD >= 0 else { return .failure("cannot open source: \(errnoText())") }
        defer { close(inFD) }

        // Sequential whole-file read: don't evict the user's page cache for it.
        _ = fcntl(inFD, F_NOCACHE, 1)
        _ = fcntl(inFD, F_RDAHEAD, 1)

        // O_NOFOLLOW closes the window between the containment check and this
        // open: if a symlink has appeared at the temp path since, refuse rather
        // than write through it.
        let outFD = open(dst.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
        guard outFD >= 0 else { return .failure("cannot create copy: \(errnoText())") }
        defer { close(outFD) }

        var hasher = options.verify ? SHA256() : nil
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            if gInterrupted != 0 { return .cancelled }

            let n = buffer.withUnsafeMutableBytes { read(inFD, $0.baseAddress, bufferSize) }
            if n < 0 {
                if errno == EINTR { continue }
                return .failure("read error: \(errnoText())")
            }
            if n == 0 { break }

            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes {
                    write(outFD, $0.baseAddress!.advanced(by: written), n - written)
                }
                if w < 0 {
                    if errno == EINTR { continue }
                    if errno == ENOSPC { return .failure("destination is full") }
                    return .failure("write error: \(errnoText())")
                }
                written += w
            }

            if hasher != nil {
                buffer.withUnsafeBytes { hasher!.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
            }

            total += Int64(n)
            progress(Int64(n))
        }

        if fsync(outFD) != 0 {
            return .failure("fsync failed: \(errnoText())")
        }

        let digest = hasher.map { $0.finalize().map { String(format: "%02x", $0) }.joined() }
        return .success(bytes: total, digest: digest)
    }

    // MARK: - Duplicate / collision handling

    private enum FileIdentity {
        case identical
        case different
    }

    private enum Placement {
        /// An identical copy is already here. Nothing to do.
        case existing(URL)
        /// Write here. Equals the base path when nothing was in the way.
        case fresh(URL)
        /// All 9999 slots are taken. A hard failure — never a silent skip.
        case exhausted
    }

    /// exFAT stores modification time at 2-second granularity, so a destination
    /// on an exFAT archive drive rounds the timestamp we wrote. Comparing
    /// exactly would call every file different and re-duplicate the whole
    /// archive on the next run.
    private static let mtimeTolerance: TimeInterval = 2

    /// Head and tail window for the content sample.
    private static let sampleWindow = 64 * 1024

    /// Is `dest` provably the same file as `item`'s source?
    ///
    /// Asymmetric on purpose. `.identical` means "do not copy", which destroys a
    /// photograph if it is wrong, so it is returned only on positive proof.
    /// Anything unreadable, missing or ambiguous answers `.different`, which
    /// costs at worst one redundant `-N` copy.
    private func identity(of item: MediaItem, matches dest: URL) -> FileIdentity {
        guard let values = try? dest.resolvingSymlinksInPath()
                .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              Int64(size) == item.size
        else { return .different }

        if let m = values.contentModificationDate,
           abs(m.timeIntervalSince(item.mtime)) > Self.mtimeTolerance {
            return .different
        }

        // Size and mtime alone cannot separate two distinct frames: the
        // tolerance above is wide enough to cover a burst, where several frames
        // share one 2-second tick, and uncompressed RAF is a fixed size for a
        // given body. The content check is what makes the tolerance safe.
        if options.verify {
            guard let a = sha256(of: item.source), let b = sha256(of: dest) else { return .different }
            return a == b ? .identical : .different
        }
        guard let a = sample(item.source, size: item.size),
              let b = sample(dest, size: item.size)
        else { return .different }
        return a == b ? .identical : .different
    }

    /// SHA-256 over the first and last 64 KB. Two distinct frames always differ
    /// inside the first window — EXIF `DateTimeOriginal` and the embedded
    /// thumbnail both live there — and the tail catches a truncated copy.
    private func sample(_ url: URL, size: Int64) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        var hasher = SHA256()
        if size <= Int64(Self.sampleWindow) * 2 {
            guard let all = try? fh.readToEnd() else { return nil }
            hasher.update(data: all)
        } else {
            guard let head = try? fh.read(upToCount: Self.sampleWindow) else { return nil }
            hasher.update(data: head)
            do { try fh.seek(toOffset: UInt64(size - Int64(Self.sampleWindow))) } catch { return nil }
            guard let tail = try? fh.read(upToCount: Self.sampleWindow) else { return nil }
            hasher.update(data: tail)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Walk `base`, `base-1`, `base-2`, … and stop at the first candidate that
    /// either already holds these bytes or does not exist.
    ///
    /// This is one function rather than two on purpose. "Has this already been
    /// imported?" and "which `-N` should it become?" are the same question asked
    /// at `i = 0` and `i > 0`, and answering them with two different predicates
    /// is what let a frame be dropped at the base path while re-runs piled up
    /// duplicates behind it.
    private func placement(of item: MediaItem, at base: URL) -> Placement {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base.path) { return .fresh(base) }
        if identity(of: item, matches: base) == .identical { return .existing(base) }

        let dir = base.deletingLastPathComponent()
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension

        for i in 1...9999 {
            let name = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return .fresh(candidate) }
            if identity(of: item, matches: candidate) == .identical { return .existing(candidate) }
        }
        return .exhausted
    }

    private func sha256(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while let chunk = try? fh.read(upToCount: bufferSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
