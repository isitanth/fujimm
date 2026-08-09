import XCTest

/// Commit 6 of the v1.1.0 plan: what a run did not do must be visible in every
/// output mode, and the byte totals must describe what was actually written.
///
/// BACKLOG.md reproductions #8 and #12.
final class ReportingTests: XCTestCase {

    private let day = "2026-06-15"

    // MARK: - Unrecognised files (reproduction #8)

    /// A scripted `fujimm --json` used to see {"status":"ok"} for a run that
    /// silently left files behind, because everything fujimm knew about what it
    /// had not copied was printed inside a `!quiet && !json` block.
    func testUnrecognisedExtensionsAppearInJSON() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)
        try writeFixture(card.images.appendingPathComponent("NOTES.XYZ"), bytes: 100, day: day)

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        let json = try XCTUnwrap(run.json, "no JSON on stdout:\n\(run.stdout)")

        let unknown = try XCTUnwrap(json["unknownExtensions"] as? [String: Int],
                                    "JSON has no unknownExtensions field")
        XCTAssertEqual(unknown["XYZ"], 1, "the .XYZ file was not reported anywhere")
    }

    func testJSONCarriesASchemaVersion() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertEqual(try XCTUnwrap(run.json)["schemaVersion"] as? Int, 1)
    }

    /// The JSON summary must stay a single parseable object even when there is
    /// something to report — the failure detail goes to stderr.
    func testFailureDetailGoesToStderrNotStdout() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)

        let unreadableDir = card.images.appendingPathComponent("SUB")
        try FileManager.default.createDirectory(at: unreadableDir, withIntermediateDirectories: true)
        try writeFixture(unreadableDir.appendingPathComponent("DSCF0002.JPG"), bytes: 500, day: day)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: unreadableDir.path)
        }

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertNotNil(run.json, "stdout must remain one parseable JSON object:\n\(run.stdout)")

        let json = try XCTUnwrap(run.json)
        let unreadable = try XCTUnwrap(json["unreadable"] as? [[String: Any]],
                                       "JSON has no unreadable field")
        XCTAssertFalse(unreadable.isEmpty, "an unreadable directory was not reported in JSON")
        XCTAssertTrue(run.stderr.contains("unreadable"),
                      "an unreadable directory was not reported on stderr:\n\(run.stderr)")
    }

    // MARK: - Byte accounting

    /// `.renamed` carried no byte count, so a collision's bytes vanished from
    /// the total, the throughput figure and the JSON — while the file was
    /// written in full. Commit 4 made this the common case rather than a rarity.
    func testRenamedFilesCountTowardsBytesWritten() throws {
        let box = try Sandbox()
        let first = try box.card("cardA")
        let second = try box.card("cardB")
        let dest = try box.directory("import")

        try writeFixture(first.images.appendingPathComponent("DSCF0001.JPG"),
                         bytes: 5_000, day: day, variant: 1)
        try writeFixture(second.images.appendingPathComponent("DSCF0001.JPG"),
                         bytes: 5_000, day: day, variant: 2)

        _ = try Harness.run(box.arguments(source: first.root, dest: dest, ["--json"]))
        let run = try Harness.run(box.arguments(source: second.root, dest: dest, ["--json"]))

        XCTAssertEqual(run.int("renamed"), 1, "the collision should have been kept alongside")
        XCTAssertEqual(run.int("bytes"), 5_000, """
            a renamed file's bytes are missing from the total — 5,000 bytes were \
            written but the run reported \(run.int("bytes") ?? -1)
            """)
    }

    // MARK: - Dry run honesty (reproduction #12)

    /// The dry-run summary hardcoded "would be saved with a -1 suffix" even when
    /// the real name would be -4.
    func testDryRunReportsTheRealCollisionName() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        let source = card.images.appendingPathComponent("DSCF0001.JPG")
        try writeFixture(source, bytes: 4_000, day: day, variant: 1)

        // Occupy DSCF0001.JPG and -1 and -2 with different content, so the next
        // free slot is -3.
        let folder = dest.appendingPathComponent("\(day)/Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["DSCF0001.JPG", "DSCF0001-1.JPG", "DSCF0001-2.JPG"] {
            try Data(repeating: 0x5A, count: 4_000).write(to: folder.appendingPathComponent(name))
        }

        let dry = try Harness.run(box.arguments(source: card.root, dest: dest, ["--dry-run"]))
        XCTAssertEqual(dry.exitCode, 0, "dry run failed:\n\(dry.stderr)")
        XCTAssertTrue(dry.stdout.contains("DSCF0001-3.JPG"), """
            the dry run did not name the real destination. Output was:
            \(dry.stdout)
            """)
        XCTAssertFalse(dry.stdout.contains("-1 suffix"),
                       "the dry run still claims a hardcoded -1 suffix")

        // And the real run must agree with what the dry run said.
        let real = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertEqual(real.int("renamed"), 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("DSCF0001-3.JPG").path
        ), "the real run did not land where the dry run predicted")
    }
}
