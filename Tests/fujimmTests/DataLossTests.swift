import XCTest

/// Commit 2 of the v1.1.0 plan: **the three assertions that fail on v1.0.0.**
///
/// This is the bar the release is judged against. Each one reproduces a path
/// where fujimm today either discards a photograph or grows the destination
/// without bound, and each is expected to stay red until its fix lands:
///
/// - `testSameSizeDifferentContentKeepsBothFrames` → Commit 4 (`fix-silent-drop`)
/// - `testRepeatedRunsAfterACollisionDoNotGrow`    → Commit 4 (`fix-rerun-duplicates`)
/// - `testSymlinkedSourceImportsExactlyOnce`       → Commit 3 (`fix-symlink-size`)
///
/// See BACKLOG.md reproductions #2, #1 and #6 respectively.
final class DataLossTests: XCTestCase {

    private let day = "2026-06-15"

    // MARK: - fix-silent-drop  (BACKLOG.md reproduction #2)

    /// Two bodies, or one body after its counter wrapped, produce `DSCF0001.JPG`
    /// twice. Uncompressed RAF is a fixed byte size for a given body, so
    /// same-name + same-size + different-content is the *normal* case when two
    /// cards merge into one day folder — not an edge case.
    ///
    /// Today `Copier.isAlreadyImported` returns true on a size match alone, so
    /// the second frame is reported as "already there", never copied, and the
    /// process exits 0. The photograph is gone with no diagnostic.
    func testSameSizeDifferentContentKeepsBothFrames() throws {
        let box = try Sandbox()
        let first = try box.card("cardA")
        let second = try box.card("cardB")
        let dest = try box.directory("import")

        let a = first.images.appendingPathComponent("DSCF0001.JPG")
        let b = second.images.appendingPathComponent("DSCF0001.JPG")
        let bytesA = try writeFixture(a, bytes: 5_000, day: day, variant: 1)
        let bytesB = try writeFixture(b, bytes: 5_000, day: day, variant: 2)

        // The premise, asserted so this test can never pass vacuously.
        XCTAssertEqual(bytesA.count, bytesB.count, "fixture must be the same size")
        XCTAssertNotEqual(bytesA.sha256Hex, bytesB.sha256Hex,
                          "fixture must differ in content")

        let runA = try Harness.run(box.arguments(source: first.root, dest: dest, ["--json"]))
        XCTAssertEqual(runA.int("copied"), 1, "first card should import:\n\(runA.stderr)")

        let runB = try Harness.run(box.arguments(source: second.root, dest: dest, ["--json"]))
        XCTAssertEqual(runB.exitCode, 0, "second import failed:\n\(runB.stderr)")

        let imported = Tree.files(under: dest)
        XCTAssertEqual(imported.count, 2, """
            the second frame was discarded — both files are 5,000 bytes with \
            different content, so both must survive.
            Destination holds: \(imported)
            Second run reported: copied=\(runB.int("copied") ?? -1) \
            skipped=\(runB.int("skipped") ?? -1)
            """)

        // Both original frames must be recoverable from the destination.
        let digests = try Set(imported.map {
            try box.sha256(of: dest.appendingPathComponent($0))
        })
        XCTAssertTrue(digests.contains(bytesA.sha256Hex), "the first frame is missing")
        XCTAssertTrue(digests.contains(bytesB.sha256Hex), "the second frame is missing")
    }

    // MARK: - fix-rerun-duplicates  (BACKLOG.md reproduction #1)

    /// Once a genuine collision has been resolved as `DSCF0001-1.JPG`, every
    /// later run must recognise that copy and do nothing.
    ///
    /// Today `uniqueDestination` only checks whether a candidate path *exists*,
    /// never whether it already holds these bytes, so each re-run appends
    /// another `-N` forever. The README's "re-running costs nothing" is false
    /// on this path.
    func testRepeatedRunsAfterACollisionDoNotGrow() throws {
        let box = try Sandbox()
        let card = try box.card("card")
        let dest = try box.directory("import")

        let source = card.images.appendingPathComponent("DSCF0001.JPG")
        try writeFixture(source, bytes: 5_000, day: day, variant: 1)

        let args = box.arguments(source: card.root, dest: dest, ["--json"])
        let initial = try Harness.run(args)
        XCTAssertEqual(initial.int("copied"), 1, "setup import failed:\n\(initial.stderr)")

        // Make the destination copy genuinely different, so every subsequent run
        // faces a real collision rather than an already-imported file.
        let landed = try XCTUnwrap(Tree.files(under: dest).first)
        let landedURL = dest.appendingPathComponent(landed)
        try Data(repeating: 0xAB, count: 6_000).write(to: landedURL)

        for pass in 1...3 {
            let run = try Harness.run(args)
            XCTAssertEqual(run.exitCode, 0, "re-run \(pass) failed:\n\(run.stderr)")
        }

        let imported = Tree.files(under: dest)
        XCTAssertEqual(imported.count, 2, """
            three re-runs against one unchanged source produced \
            \(imported.count) files instead of 2 (the altered file, plus one \
            copy of the real frame).
            Destination holds: \(imported)
            """)
    }

    // MARK: - fix-symlink-size  (BACKLOG.md reproduction #6)

    /// Reachable through the advertised `fujimm --source ~/old-offload`
    /// workflow, where rsync and backup trees routinely contain symlinks.
    ///
    /// `Scanner` stats with `attributesOfItem`, which does not traverse
    /// symlinks, while `Copier` opens with `open(O_RDONLY)`, which does. So
    /// `MediaItem.size` is the link's own byte length, the size comparison
    /// against the real destination file never matches, and every run mints a
    /// fresh `-1`, `-2`, `-3`.
    func testSymlinkedSourceImportsExactlyOnce() throws {
        let box = try Sandbox()
        let card = try box.card("offload")
        let dest = try box.directory("import")

        let real = try box.directory("originals").appendingPathComponent("BIG.JPG")
        try writeFixture(real, bytes: 512 * 1024, day: day)

        let link = card.images.appendingPathComponent("DSCF0004.JPG")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let args = box.arguments(source: card.root, dest: dest, ["--json"])
        for pass in 1...3 {
            let run = try Harness.run(args)
            XCTAssertEqual(run.exitCode, 0, "run \(pass) failed:\n\(run.stderr)")
        }

        let imported = Tree.files(under: dest)
        XCTAssertEqual(imported.count, 1, """
            a symlinked source was imported \(imported.count) times across three \
            runs. Destination holds: \(imported)
            """)

        if let only = imported.first {
            XCTAssertEqual(try box.size(of: dest.appendingPathComponent(only)), 512 * 1024,
                           "the copy should be the link's target, at full size")
        }
    }
}
