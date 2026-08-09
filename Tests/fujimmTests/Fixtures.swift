import Foundation
import CryptoKit

// MARK: - Deterministic content

/// Stable across processes, unlike `String.hashValue`, which Swift seeds
/// randomly per run. Fixture bytes must be reproducible so a tree digest taken
/// in one process means the same thing in the next.
func stableSeed(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x100_0000_01b3
    }
    return h
}

/// Pseudo-random bytes from a linear congruential generator. Same seed and
/// count always produce the same bytes.
func deterministicBytes(count: Int, seed: UInt64) -> Data {
    var state = seed
    var data = Data(capacity: count)
    for _ in 0..<count {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        data.append(UInt8(truncatingIfNeeded: state >> 33))
    }
    return data
}

func middayUTC(_ day: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: "\(day) 12:00:00")!
}

/// Write `bytes` deterministic bytes at `url` and stamp its mtime to midday UTC
/// on `day`. `variant` changes the content without changing the length — which
/// is exactly the same-name/same-size/different-content case that
/// `fix-silent-drop` is about.
@discardableResult
func writeFixture(_ url: URL, bytes: Int, day: String, variant: UInt64 = 0) throws -> Data {
    let data = deterministicBytes(
        count: bytes,
        seed: stableSeed(url.lastPathComponent) &+ variant &* 0x9E37_79B9_7F4A_7C15
    )
    try data.write(to: url)
    try FileManager.default.setAttributes(
        [.modificationDate: middayUTC(day)],
        ofItemAtPath: url.path
    )
    return data
}

// MARK: - Sandbox

/// A scratch directory for tests that need more than the one standard fixture
/// card — several cards, a pre-populated destination, or a symlinked source.
final class Sandbox {

    struct CardDir {
        /// Pass this to `--source`.
        let root: URL
        /// Write media here: `<root>/DCIM/100_FUJI`.
        let images: URL
    }

    let container: URL

    init() throws {
        container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fujimm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: container) }

    func card(_ name: String) throws -> CardDir {
        let root = container.appendingPathComponent(name)
        let images = root.appendingPathComponent("DCIM/100_FUJI")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        return CardDir(root: root, images: images)
    }

    func directory(_ name: String) throws -> URL {
        let url = container.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Standard argument list: pinned timezone so day grouping is reproducible
    /// regardless of the machine's own.
    func arguments(source: URL, dest: URL, _ extra: [String] = []) -> [String] {
        ["--source", source.path, "--dest", dest.path, "--tz", "UTC"] + extra
    }

    func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return data.sha256Hex
    }

    func size(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? -1
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
