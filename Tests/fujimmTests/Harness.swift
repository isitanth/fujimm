import Foundation
import CryptoKit
import XCTest

// MARK: - Running the binary

/// One completed run of the built `fujimm` binary.
struct RunResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    /// The `--json` summary, parsed. fujimm prints exactly one JSON object on
    /// stdout under `--json`; progress and errors go to stderr.
    var json: [String: Any]? {
        guard let line = stdout
            .split(separator: "\n")
            .last(where: { $0.hasPrefix("{") })
        else { return nil }
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func int(_ key: String) -> Int? { json?[key] as? Int }
    func days() -> [String] { (json?["days"] as? [String]) ?? [] }
}

enum Harness {

    /// Locate the executable SwiftPM just built. The test bundle sits next to it
    /// in the build directory; `swift build --show-bin-path` is the fallback for
    /// layouts where it does not.
    static func binaryURL() throws -> URL {
        let bundleDir = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        let adjacent = bundleDir.appendingPathComponent("fujimm")
        if FileManager.default.isExecutableFile(atPath: adjacent.path) { return adjacent }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["swift", "build", "--show-bin-path"]
        p.currentDirectoryURL = packageRoot()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = URL(fileURLWithPath: path).appendingPathComponent("fujimm")
        guard FileManager.default.isExecutableFile(atPath: fallback.path) else {
            throw HarnessError.binaryNotFound(bundleDir.path)
        }
        return fallback
    }

    /// Tests/fujimmTests/Harness.swift → the package root.
    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // fujimmTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
    }

    @discardableResult
    static func run(_ arguments: [String]) throws -> RunResult {
        let p = Process()
        p.executableURL = try binaryURL()
        p.arguments = arguments

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // NO_COLOR keeps ANSI escapes out of the strings we parse.
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env

        try p.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        return RunResult(
            exitCode: p.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    enum HarnessError: Error, CustomStringConvertible {
        case binaryNotFound(String)
        var description: String {
            switch self {
            case .binaryNotFound(let dir):
                return "could not find the fujimm binary near \(dir) — run `swift build` first"
            }
        }
    }

    private final class BundleToken {}
}

// MARK: - Fixture card

/// A synthetic card tree. No camera, no SD card, no committed binary fixtures —
/// random bytes plus fabricated mtimes are enough to exercise scan, grouping,
/// junk filtering and directory pruning.
///
/// Files carry no readable EXIF, so `DateResolver` falls through to
/// `filesystemDate`, which formats mtime in the run's timezone. Every test
/// therefore passes `--tz UTC` and every mtime is midday UTC, which makes the
/// day-grouping deterministic regardless of the machine's own timezone.
final class FixtureCard {

    let root: URL              // the "card"
    let destination: URL       // where imports land — always outside the card
    private let container: URL

    /// Day A and day B, as fujimm will render them under `--tz UTC`.
    static let dayA = "2026-06-15"
    static let dayB = "2026-07-19"

    /// Files fujimm is expected to import from the default fixture.
    static let expectedMediaCount = 3
    static let expectedDays = [dayA, dayB]

    init() throws {
        container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fujimm-tests-\(UUID().uuidString)")
        root = container.appendingPathComponent("card")
        destination = container.appendingPathComponent("import")
        try build()
    }

    deinit { try? FileManager.default.removeItem(at: container) }

    private func build() throws {
        let fm = FileManager.default
        let fuji = root.appendingPathComponent("DCIM/100_FUJI")
        try fm.createDirectory(at: fuji, withIntermediateDirectories: true)

        // Real media, two distinct days.
        try write(fuji.appendingPathComponent("DSCF0001.JPG"), bytes: 5_000, day: Self.dayA)
        try write(fuji.appendingPathComponent("DSCF0002.RAF"), bytes: 8_000, day: Self.dayA)
        try write(fuji.appendingPathComponent("DSCF0003.MOV"), bytes: 3_000, day: Self.dayB)

        // macOS bookkeeping — Formats.isJunk must skip both.
        try write(fuji.appendingPathComponent("._DSCF0001.JPG"), bytes: 82, day: Self.dayA)
        try write(fuji.appendingPathComponent(".DS_Store"), bytes: 120, day: Self.dayA)

        // Camera-internal directories — Formats.ignoredDirectories must prune these.
        try fm.createDirectory(at: root.appendingPathComponent("DCIM/MISC"),
                               withIntermediateDirectories: true)
        try write(root.appendingPathComponent("DCIM/MISC/INDEX.DAT"), bytes: 64, day: Self.dayA)

        // FFDB at the volume root is what makes hasFujifilmSignature true.
        try fm.createDirectory(at: root.appendingPathComponent("FFDB"),
                               withIntermediateDirectories: true)

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    private func write(_ url: URL, bytes: Int, day: String) throws {
        try writeFixture(url, bytes: bytes, day: day)
    }

    /// The standard argument list: never touches a real card, never a real
    /// destination, and pins the timezone so day grouping is reproducible.
    func arguments(_ extra: [String] = []) -> [String] {
        ["--source", root.path, "--dest", destination.path, "--tz", "UTC"] + extra
    }
}

// MARK: - Tree digest

enum Tree {

    /// A digest over every file under `url`: relative path, size, mtime and
    /// content. Any write, truncation, rename, deletion or timestamp change
    /// anywhere in the tree changes the result.
    ///
    /// Hidden files are deliberately included — an AppleDouble stub or a stray
    /// `.part` appearing on the card is exactly the kind of modification the
    /// read-only promise forbids.
    static func digest(of url: URL) throws -> String {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return "empty" }

        var entries: [String] = []
        let base = url.standardizedFileURL.path

        while let item = walker.nextObject() as? URL {
            let values = try item.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            let relative = item.standardizedFileURL.path.replacingOccurrences(
                of: base + "/", with: ""
            )
            guard values.isRegularFile == true else {
                entries.append("dir \(relative)")
                continue
            }
            let content = try Data(contentsOf: item)
            let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? -1
            entries.append("file \(relative) \(values.fileSize ?? -1) \(mtime) \(hash)")
        }

        entries.sort()
        let combined = entries.joined(separator: "\n")
        return SHA256.hash(data: Data(combined.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Every regular file under `url`, as paths relative to it.
    static func files(under url: URL) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        let base = url.standardizedFileURL.path
        var out: [String] = []
        while let item = walker.nextObject() as? URL {
            let isFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile
            if isFile == true {
                out.append(item.standardizedFileURL.path
                    .replacingOccurrences(of: base + "/", with: ""))
            }
        }
        return out.sorted()
    }
}
