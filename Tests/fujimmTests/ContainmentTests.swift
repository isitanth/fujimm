import XCTest

/// Commit 5 of the v1.1.0 plan: nothing fujimm writes may land outside `--dest`.
///
/// BACKLOG.md reproduction #3. The escape used to be masked by the silent-drop
/// bug — an escape aimed at the card's own file was skipped as "already
/// imported" — so it only became visible once Commit 4 landed.
final class ContainmentTests: XCTestCase {

    private let day = "2026-06-15"

    private func card(in box: Sandbox) throws -> Sandbox.CardDir {
        let c = try box.card("card")
        try writeFixture(c.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)
        return c
    }

    // MARK: - The escape itself

    func testBucketNameCannotEscapeTheDestination() throws {
        let box = try Sandbox()
        let c = try card(in: box)
        let dest = try box.directory("import/inner")

        let run = try Harness.run(
            box.arguments(source: c.root, dest: dest, ["--photos-dir", "../../../escaped"])
        )
        XCTAssertEqual(run.exitCode, 2, "a '..' bucket name must be rejected:\n\(run.stdout)")

        let outside = box.container.appendingPathComponent("escaped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path),
                       "files were written outside --dest")
    }

    func testDateFormatCannotEscapeTheDestination() throws {
        let box = try Sandbox()
        let c = try card(in: box)
        let dest = try box.directory("import/inner")

        for pattern in ["../..", "..", "yyyy'/../'MM"] {
            let run = try Harness.run(
                box.arguments(source: c.root, dest: dest, ["--date-format", pattern])
            )
            XCTAssertEqual(run.exitCode, 2,
                           "--date-format '\(pattern)' must be rejected:\n\(run.stdout)")
        }
    }

    /// A symlink planted inside the destination must not be traversed. This is
    /// the case a containment check alone does not stop, because the directory
    /// creation is what escapes.
    func testSymlinkInsideDestinationIsNotTraversed() throws {
        let box = try Sandbox()
        let c = try card(in: box)
        let dest = try box.directory("import")
        let outside = try box.directory("outside")

        // The day folder fujimm is about to create is instead a symlink pointing
        // out of the destination.
        try FileManager.default.createSymbolicLink(
            at: dest.appendingPathComponent(day),
            withDestinationURL: outside
        )

        let run = try Harness.run(box.arguments(source: c.root, dest: dest))
        XCTAssertNotEqual(run.exitCode, 0, "the run should not report success")

        XCTAssertTrue(Tree.files(under: outside).isEmpty, """
            a symlink inside the destination was followed and files were written \
            outside it: \(Tree.files(under: outside))
            """)
    }

    // MARK: - What must keep working

    /// The README documents this, so validation must not break it.
    func testNestedDateFormatStillNests() throws {
        let box = try Sandbox()
        let c = try card(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(
            box.arguments(source: c.root, dest: dest, ["--json", "--date-format", "yyyy/MM/dd"])
        )
        XCTAssertEqual(run.exitCode, 0, "nested date format was rejected:\n\(run.stdout)")
        XCTAssertEqual(Tree.files(under: dest), ["2026/06/15/Photos/DSCF0001.JPG"])
    }

    /// Undocumented, but it works today, so rejecting `/` outright would be a
    /// silent breaking change. Only `..` is rejected.
    func testNestedBucketNameStillWorks() throws {
        let box = try Sandbox()
        let c = try card(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(
            box.arguments(source: c.root, dest: dest, ["--json", "--photos-dir", "Raw/Fuji"])
        )
        XCTAssertEqual(run.exitCode, 0, "a nested bucket name was rejected:\n\(run.stdout)")
        XCTAssertEqual(Tree.files(under: dest), ["\(day)/Raw/Fuji/DSCF0001.JPG"])
    }

    // MARK: - --dest

    /// `--dest "$UNSET"` used to resolve to the current working directory and
    /// import gigabytes into wherever the script happened to run.
    func testEmptyDestinationIsRejected() throws {
        let box = try Sandbox()
        let c = try card(in: box)

        for value in ["", "   "] {
            let run = try Harness.run(["--source", c.root.path, "--dest", value, "--tz", "UTC"])
            XCTAssertEqual(run.exitCode, 2,
                           "--dest '\(value)' must be rejected:\n\(run.stdout)\n\(run.stderr)")
        }
    }

    /// The card guard: importing a card into itself.
    func testDestinationOnTheCardIsRefused() throws {
        let box = try Sandbox()
        let c = try card(in: box)

        let run = try Harness.run(
            box.arguments(source: c.root, dest: c.root.appendingPathComponent("import"))
        )
        XCTAssertEqual(run.exitCode, 2, "importing a card into itself must be refused")
        XCTAssertTrue(run.stderr.contains("card"), "the message should explain why:\n\(run.stderr)")
    }
}
