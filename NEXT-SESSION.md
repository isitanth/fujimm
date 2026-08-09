# Handoff — resume here

Written 2026-08-07. Read this first, then [RELEASE-1.1.0.md](RELEASE-1.1.0.md).

---

## Repo state as of this handoff

| | |
|---|---|
| Branch | `main`, in sync with `origin/main` |
| HEAD | `008e23c` — "Update README.md" (pulled from GitHub this session) |
| Working tree | Clean except two **untracked** files: `BACKLOG.md`, `RELEASE-1.1.0.md` (+ this file) |
| Build | `swift build` succeeds in ~1.3 s |
| Tests | **None.** No `Tests/` directory, no `.testTarget` in `Package.swift` |
| Source | Unchanged from v1.0.0. **No code has been modified in any session so far.** |

Everything to date is planning. Not one line of `Sources/` has been touched.

---

## The three documents

| File | What it is |
|---|---|
| `BACKLOG.md` | Full audit of v1.0.0 — 17 fixes, 11 improvements, 9 tech items, 11 features, won't-dos, dependency chains, 16 hand-verified reproductions. The long-term reference. |
| `RELEASE-1.1.0.md` | **The plan to execute.** Scope, the identity-predicate design, nine commits, definition of done, test fixture, guardrails, risk register. |
| `NEXT-SESSION.md` | This file. |

---

## Open decision — resolve this first

**Version label: `1.1.0` (current default) or `1.0.1`?**

The plan currently says 1.1.0 because three items change observable contracts: `--eject` starts
refusing incomplete runs, "nothing to import" stops exiting 1, unreadable directories start
exiting 3.

- **Keep 1.1.0** → execute the plan as written. No changes needed.
- **Switch to 1.0.1** → it becomes a true patch: **delete Commit 7 entirely** and **drop the
  exit-3 half of Commit 6**, moving both to the next minor. Everything else survives intact —
  the identity predicate, path escape, dest guard, symlink size, the JSON/stderr reporting
  additions, and the eject gate are all non-breaking. Then relabel the docs.

If no decision is made, 1.1.0 stands.

---

## What to paste into the next session

> Read RELEASE-1.1.0.md and NEXT-SESSION.md in this repo, then start Commit 1 — the test
> harness with the four green assertions. Do not touch Sources/ in that commit.

That is enough. Do **not** ask it to re-read the whole backlog or re-audit the source; that
work is done and re-doing it is the expensive path (see below).

---

## Do not re-derive this — it is already verified

A cold session will want to re-audit. It should not. The following was established by reading
`Copier.swift`, `Scanner.swift`, `main.swift`, `Options.swift` and `Formats.swift` end to end,
and by hand-testing against a real build:

- All seven original v1.1.0 findings hold at their cited line numbers.
- `MediaItem` has **no mtime** — `date` is the EXIF capture date, not the filesystem mtime.
  `Scanner.swift:85` already holds the attributes dictionary, so adding it costs zero I/O.
  This is why Commit 3 precedes Commit 4.
- `CopyOutcome.renamed` carries **no byte count** (`Copier.swift:11`), so renamed files' bytes
  are missing from `copiedBytes`, the throughput rate and the JSON `"bytes"` field. Latent
  today; Commit 4 makes it prominent.
- The temp filename derives from `item.filename` (`Copier.swift:95`), not `dest` — safe only
  because the copy loop is serial. Comment it in Commit 4; do not "fix" it now.
- `Formats.isJunk` (`Formats.swift:75`) treats **any** dotfile as junk, so orphan
  `.fujimm-*.part` files are invisible to a scan. The test harness must assert on the
  filesystem directly.
- A SwiftPM `.testTarget` attaches to an `executableTarget` and `@testable import fujimm`
  reaches every type — **no library split is needed**. But `main.swift`'s top-level statements
  are unreachable from a test host, so the harness spawns the binary via
  `swift build --show-bin-path`.
- The README's line numbers moved when it was updated from GitHub this session.
  `BACKLOG.md`'s citations were corrected and re-verified; they are accurate against `008e23c`.

---

## The nine commits

Detail for each is in [RELEASE-1.1.0.md](RELEASE-1.1.0.md#the-commit-sequence). Only 3 → 4 is a
hard ordering constraint; 5 is independent and can move.

| # | Commit | Closes | Done when |
|---|---|---|---|
| 1 | Test harness, green | `fix-test-net` ½ | `swift test` green, 4 assertions |
| 2 | Add 3 failing assertions | `fix-test-net` ½ | Exactly 3 red — this is the bar |
| 3 | `MediaItem`: size + mtime | `fix-symlink-size` | Assertion 7 green; symlink plans as 500 KB not 115 B |
| 4 | **The identity predicate** | `fix-silent-drop`, `fix-rerun-duplicates` | Assertions 5, 6 green; reproductions #1, #2 flip |
| 5 | Destination containment | `fix-path-escape`, `fix-dest-guard` | Reproduction #3 flips; nested date format still nests |
| 6 | Reporting truth | `fix-scan-failures-invisible` + 2 new | Reproductions #8, #12 flip |
| 7 | Exit contract *(breaking)* | `imp-exit-code-semantics` | Reproduction #11 flips |
| 8 | Eject gate | `fix-eject-gate`, ½ `fix-dead-flags` | Reproduction #16 flips |
| 9 | CHANGELOG, version, tag | — | CHANGELOG names the data-loss bug |

**Commit 4 is the one that matters.** Read
[The one design decision](RELEASE-1.1.0.md#the-one-design-decision) before writing any of it —
the two bugs it closes pull in opposite directions, and the 2-second mtime tolerance
(for exFAT destinations) is the detail most likely to be got wrong.

---

## Optional housekeeping

Nothing here is required — the files are on disk and survive regardless.

- The three planning docs are untracked. Committing them gives you history and a remote
  backup: `git add BACKLOG.md RELEASE-1.1.0.md NEXT-SESSION.md && git commit`
- `.claude/settings.local.json` is neither tracked nor ignored, and holds local absolute
  paths. It is scheduled for `.gitignore` in Commit 9, but is worth adding sooner if you plan
  to `git add -A`.
