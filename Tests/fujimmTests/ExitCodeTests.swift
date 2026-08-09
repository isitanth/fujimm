import XCTest

/// Commit 7 of the v1.1.0 plan: the exit contract.
///
/// The one deliberately breaking change in this release, which is why it is
/// isolated in its own commit. BACKLOG.md reproduction #11.
final class ExitCodeTests: XCTestCase {

    private let day = "2026-06-15"

    // MARK: - Nothing to import is not a failure (reproduction #11)

    /// `fujimm --json && post-process` treated a fully-imported card as an
    /// error, because "everything is already safe" shared exit 1 with "I could
    /// not find your card".
    func testFullyImportedCardExitsZero() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)

        let first = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(first.int("copied"), 1)

        // Second run has nothing new — but it still finds files, so it is not
        // the empty case. Delete the source to reach that.
        try FileManager.default.removeItem(
            at: card.images.appendingPathComponent("DSCF0001.JPG")
        )
        let empty = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertEqual(empty.exitCode, 0, "an empty card is not a failure:\n\(empty.stdout)")
        XCTAssertEqual(empty.json?["status"] as? String, "nothing-to-import")
    }

    /// The escape hatch for anyone scripting against the old behaviour.
    func testFailOnEmptyRestoresExitOne() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")

        let run = try Harness.run(
            box.arguments(source: card.root, dest: dest, ["--fail-on-empty"])
        )
        XCTAssertEqual(run.exitCode, 1, "--fail-on-empty should restore exit 1")
    }

    // MARK: - Unreadable content is a failure

    /// Scanner collects unreadable directories and keeps walking, but they never
    /// became MediaItems and so never reached failedCount. An entire unreadable
    /// DCIM subfolder used to produce {"status":"ok"} and exit 0 — a success
    /// signal from a run that left photographs on the card.
    func testUnreadableDirectoryExitsThree() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)

        let locked = card.images.appendingPathComponent("LOCKED")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try writeFixture(locked.appendingPathComponent("DSCF0002.JPG"), bytes: 500, day: day)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: locked.path)
        }

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--json"]))
        XCTAssertEqual(run.exitCode, 3, """
            an unreadable folder means photographs are still on the card, so the \
            run must not report success. stdout:
            \(run.stdout)
            """)
        XCTAssertEqual(run.json?["status"] as? String, "partial")
    }

    // MARK: - Codes that must not change

    func testBadArgumentsStillExitTwo() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")

        let unknown = try Harness.run(box.arguments(source: card.root, dest: dest, ["--nope"]))
        XCTAssertEqual(unknown.exitCode, 2)

        let badSource = try Harness.run(["--source", "/no/such/folder", "--dest", dest.path])
        XCTAssertEqual(badSource.exitCode, 2)
    }

    func testSuccessfulImportStillExitsZero() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)

        let run = try Harness.run(box.arguments(source: card.root, dest: dest))
        XCTAssertEqual(run.exitCode, 0)
    }
}
