import XCTest

/// Commit 8 of the v1.1.0 plan: `--eject` must not eject a card that still
/// holds photographs this run did not copy.
///
/// Eject is the step immediately before a photographer formats the card in
/// camera, so it is the highest-consequence decision the tool makes. The old
/// gate was `failedCount == 0`, which ignored every filter.
///
/// A fixture card is a plain directory, so `Volumes.eject` is never reached —
/// `cards where c.isRemovable` is false. These tests assert the *decision* and
/// the explanation, which is the part that was wrong.
final class EjectGateTests: XCTestCase {

    private let day = "2026-06-15"

    /// Card with both a still and a clip.
    private func mixedCard(in box: Sandbox) throws -> Sandbox.CardDir {
        let card = try box.card("card")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)
        try writeFixture(card.images.appendingPathComponent("DSCF0002.MOV"), bytes: 4_000, day: day)
        return card
    }

    /// The headline case: `--only photos --eject` deliberately leaves every
    /// video behind and then ejects the card.
    func testRefusesToEjectWhenAFilterLeftFilesBehind() throws {
        let box = try Sandbox()
        let card = try mixedCard(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(
            box.arguments(source: card.root, dest: dest, ["--only", "photos", "--eject"])
        )
        XCTAssertTrue(run.stderr.contains("Not ejecting"), """
            --only photos --eject left a video on the card and said nothing. \
            stderr was:
            \(run.stderr)
            """)
        XCTAssertTrue(run.stderr.contains("skipped by a filter"),
                      "the refusal should say what was left:\n\(run.stderr)")
    }

    func testRefusesToEjectWhenADateFilterLeftFilesBehind() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")
        try writeFixture(card.images.appendingPathComponent("DSCF0001.JPG"), bytes: 3_000, day: day)
        try writeFixture(card.images.appendingPathComponent("DSCF0003.JPG"),
                         bytes: 3_000, day: "2026-07-19")

        let run = try Harness.run(
            box.arguments(source: card.root, dest: dest, ["--since", "2026-07-01", "--eject"])
        )
        XCTAssertTrue(run.stderr.contains("Not ejecting"),
                      "--since left an earlier day on the card:\n\(run.stderr)")
    }

    func testRefusesToEjectWhenAFolderCouldNotBeRead() throws {
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

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--eject"]))
        XCTAssertTrue(run.stderr.contains("Not ejecting"),
                      "an unreadable folder should block eject:\n\(run.stderr)")
        XCTAssertTrue(run.stderr.contains("could not be read"),
                      "the refusal should name the reason:\n\(run.stderr)")
    }

    /// `-y` is the override. Before this commit the flag was parsed and read
    /// nowhere at all.
    func testYesOverridesTheRefusal() throws {
        let box = try Sandbox()
        let card = try mixedCard(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(
            box.arguments(source: card.root, dest: dest, ["--only", "photos", "--eject", "-y"])
        )
        XCTAssertFalse(run.stderr.contains("Not ejecting"),
                       "-y should override the refusal:\n\(run.stderr)")
        XCTAssertTrue(run.stderr.contains("Ejecting anyway"),
                      "the override should still say what is being left:\n\(run.stderr)")
    }

    /// A complete import must not be second-guessed.
    func testCleanImportDoesNotRefuse() throws {
        let box = try Sandbox()
        let card = try mixedCard(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["--eject"]))
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertFalse(run.stderr.contains("Not ejecting"),
                       "a complete import should be free to eject:\n\(run.stderr)")
    }

    /// `-y` must be a real flag, not something accepted and ignored.
    func testYesIsAcceptedAsAFlag() throws {
        let box = try Sandbox()
        let card = try mixedCard(in: box)
        let dest = try box.directory("import")

        let run = try Harness.run(box.arguments(source: card.root, dest: dest, ["-y"]))
        XCTAssertEqual(run.exitCode, 0)

        let help = try Harness.run(["--help"])
        XCTAssertTrue(help.stdout.contains("--yes"),
                      "--yes is accepted but missing from --help")
    }
}
