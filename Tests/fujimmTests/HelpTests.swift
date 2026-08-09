import XCTest

/// The README says "`fujimm --help` lists everything". Four flags were accepted
/// by the parser and absent from the help text, which is how that sentence
/// became false without anyone noticing.
final class HelpTests: XCTestCase {

    /// Every long flag `OptionsParser` accepts. Kept here deliberately: the
    /// parser's flag list is a switch statement rather than data, so there is
    /// nothing to enumerate at runtime. Adding a flag means adding it here,
    /// which is the point — the test fails until it is documented too.
    private let acceptedFlags = [
        "--all-cards", "--date-format", "--dest", "--destination", "--dry-run",
        "--eject", "--fail-on-empty", "--flat", "--help", "--json", "--list",
        "--only", "--other", "--other-dir", "--overwrite", "--photos-dir",
        "--quiet", "--since", "--source", "--timezone", "--tz", "--until",
        "--verbose", "--verify", "--version", "--video-date", "--videos-dir",
        "--yes",
    ]

    func testEveryAcceptedFlagAppearsInHelp() throws {
        let help = try Harness.run(["--help"])
        XCTAssertEqual(help.exitCode, 0)

        let missing = acceptedFlags.filter { !help.stdout.contains($0) }
        XCTAssertTrue(missing.isEmpty, """
            accepted by OptionsParser but absent from --help: \(missing.joined(separator: ", "))
            """)
    }

    /// An unknown flag must be an error, not a silent no-op.
    func testUnknownFlagIsRejected() throws {
        let run = try Harness.run(["--not-a-flag"])
        XCTAssertEqual(run.exitCode, 2)
    }

    func testVersionMatchesTheChangelog() throws {
        let run = try Harness.run(["--version"])
        XCTAssertEqual(run.exitCode, 0)
        let reported = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let changelog = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CHANGELOG.md"),
            encoding: .utf8
        )
        let latest = changelog
            .split(separator: "\n")
            .first { $0.hasPrefix("## ") }
            .map { $0.dropFirst(3).trimmingCharacters(in: .whitespaces) }

        XCTAssertEqual(reported, "fujimm \(latest ?? "?")", """
            --version reports '\(reported)' but the newest CHANGELOG entry is \
            '\(latest ?? "none")'
            """)
    }
}
