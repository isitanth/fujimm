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

        if options.dryRun {
            // Still report the collision decision so a dry run predicts reality.
            if fm.fileExists(atPath: dest.path) {
                if isAlreadyImported(source: item.source, dest: dest, size: item.size) {
                    return CopyRecord(item: item, outcome: .skippedIdentical, destination: dest)
                }
                if options.overwrite {
                    return CopyRecord(item: item, outcome: .wouldCopy, destination: dest)
                }
                let alt = uniqueDestination(dest)
                if alt != dest {
                    return CopyRecord(item: item, outcome: .renamed(to: alt.lastPathComponent),
                                      destination: alt)
                }
            }
            return CopyRecord(item: item, outcome: .wouldCopy, destination: dest)
        }

        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        } catch {
            return CopyRecord(item: item,
                              outcome: .failed("cannot create folder: \(error.localizedDescription)"),
                              destination: dest)
        }

        var didOverwrite = false
        var didRename = false

        if fm.fileExists(atPath: dest.path) {
            if isAlreadyImported(source: item.source, dest: dest, size: item.size) {
                return CopyRecord(item: item, outcome: .skippedIdentical, destination: dest)
            }
            if options.overwrite {
                didOverwrite = true
            } else {
                let alt = uniqueDestination(dest)
                // uniqueDestination also detects an existing identical `-1` copy
                if alt == dest {
                    return CopyRecord(item: item, outcome: .skippedIdentical, destination: dest)
                }
                dest = alt
                didRename = true
            }
        }

        // Write to a sibling temp file and rename into place, so an interrupted
        // run can never leave a truncated file wearing the real name.
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
            if let attrs = try? fm.attributesOfItem(atPath: item.source.path) {
                var keep: [FileAttributeKey: Any] = [:]
                if let m = attrs[.modificationDate] { keep[.modificationDate] = m }
                if let c = attrs[.creationDate] { keep[.creationDate] = c }
                try? fm.setAttributes(keep, ofItemAtPath: temp.path)
            }

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

        let outFD = open(dst.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
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

    /// A file already at the destination counts as imported when the sizes match.
    /// With --verify we go further and compare content before skipping.
    private func isAlreadyImported(source: URL, dest: URL, size: Int64) -> Bool {
        guard sameSize(dest, size) else { return false }
        guard options.verify else { return true }
        guard let a = sha256(of: source), let b = sha256(of: dest) else { return false }
        return a == b
    }

    private func sameSize(_ url: URL, _ size: Int64) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let existing = (attrs[.size] as? NSNumber)?.int64Value else { return false }
        return existing == size
    }

    /// Produce `DSCF6810-1.RAF`, `-2`, … Returns the original URL unchanged if an
    /// existing numbered copy already holds the same bytes (nothing to do).
    private func uniqueDestination(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        for i in 1...9999 {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
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
