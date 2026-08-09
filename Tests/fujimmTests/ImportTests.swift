import XCTest

/// Commit 1 of the v1.1.0 plan: four assertions that pass on v1.0.0.
///
/// They exist to pin behaviour that is currently correct, so the fixes in
/// Commits 3–8 cannot regress it. The assertions that *fail* today — the
/// data-loss cases — arrive in Commit 2.
final class ImportTests: XCTestCase {

    // MARK: - 1. The card is read-only, structurally

    /// The README's headline promise, mechanically enforced: hash the whole card
    /// tree before and after a real import and require byte-identity.
    ///
    /// This is the assertion that would have caught `fix-path-escape`, where a
    /// crafted `--photos-dir` walks the destination back onto the card.
    func testCardIsUnmodifiedByAFullImport() throws {
        let card = try FixtureCard()
        let before = try Tree.digest(of: card.root)

        let run = try Harness.run(card.arguments())
        XCTAssertEqual(run.exitCode, 0, "import failed:\n\(run.stderr)")

        let after = try Tree.digest(of: card.root)
        XCTAssertEqual(before, after, """
            the card tree changed during an import.
            Files now on the card:
            \(Tree.files(under: card.root).joined(separator: "\n"))
            """)
    }

    /// Same promise, under the flags most likely to reach unusual write paths.
    func testCardIsUnmodifiedUnderVerifyAndFlat() throws {
        let card = try FixtureCard()
        let before = try Tree.digest(of: card.root)

        let run = try Harness.run(card.arguments(["--verify", "--flat"]))
        XCTAssertEqual(run.exitCode, 0, "import failed:\n\(run.stderr)")

        XCTAssertEqual(try Tree.digest(of: card.root), before)
    }

    // MARK: - 2. The --json summary describes the run

    func testJSONSummaryReportsScanCountsAndDays() throws {
        let card = try FixtureCard()

        let run = try Harness.run(card.arguments(["--json"]))
        XCTAssertEqual(run.exitCode, 0, "import failed:\n\(run.stderr)")

        let json = try XCTUnwrap(run.json, "no JSON object on stdout:\n\(run.stdout)")
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(run.int("scanned"), FixtureCard.expectedMediaCount,
                       "junk files or pruned directories leaked into the scan")
        XCTAssertEqual(run.int("copied"), FixtureCard.expectedMediaCount)
        XCTAssertEqual(run.int("failed"), 0)
        XCTAssertEqual(run.days(), FixtureCard.expectedDays,
                       "day grouping did not match the fabricated mtimes")

        // And the files really are on disk, in day/bucket folders.
        let imported = Tree.files(under: card.destination)
        XCTAssertEqual(imported.count, FixtureCard.expectedMediaCount)
        XCTAssertTrue(imported.contains("\(FixtureCard.dayA)/Photos/DSCF0001.JPG"),
                      "unexpected layout: \(imported)")
        XCTAssertTrue(imported.contains("\(FixtureCard.dayB)/Videos/DSCF0003.MOV"),
                      "unexpected layout: \(imported)")
    }

    // MARK: - 3. Re-running costs nothing

    func testSecondRunCopiesNothing() throws {
        let card = try FixtureCard()

        let first = try Harness.run(card.arguments(["--json"]))
        XCTAssertEqual(first.int("copied"), FixtureCard.expectedMediaCount)

        let second = try Harness.run(card.arguments(["--json"]))
        XCTAssertEqual(second.exitCode, 0, "re-run failed:\n\(second.stderr)")
        XCTAssertEqual(second.int("copied"), 0, "a re-run copied files again")
        XCTAssertEqual(second.int("skipped"), FixtureCard.expectedMediaCount)

        XCTAssertEqual(Tree.files(under: card.destination).count,
                       FixtureCard.expectedMediaCount,
                       "the second run added files to the destination")
    }

    // MARK: - 4. A dry run predicts the real run

    /// The dry-run contract nothing currently checks: what `--dry-run` says it
    /// would copy is what a subsequent real run does copy.
    func testDryRunPredictsTheRealRun() throws {
        let card = try FixtureCard()

        let dry = try Harness.run(card.arguments(["--json", "--dry-run"]))
        XCTAssertEqual(dry.exitCode, 0, "dry run failed:\n\(dry.stderr)")
        XCTAssertEqual(dry.json?["dryRun"] as? Bool, true)
        let planned = try XCTUnwrap(dry.int("planned"))

        XCTAssertTrue(Tree.files(under: card.destination).isEmpty,
                      "--dry-run wrote to the destination")

        let real = try Harness.run(card.arguments(["--json"]))
        XCTAssertEqual(real.int("copied"), planned,
                       "the dry run predicted \(planned) files, the real run copied "
                       + "\(real.int("copied").map(String.init) ?? "nil")")
    }
}
