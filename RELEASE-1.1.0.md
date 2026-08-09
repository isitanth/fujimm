# fujimm v1.1.0 — "it does not lose photographs"

The next release. Scope is closed: **every path that can silently discard a frame, write
outside the destination, or report success while leaving photographs behind.** Nothing else.

Derived from [BACKLOG.md](BACKLOG.md), then re-grounded by reading `Copier.swift`,
`Scanner.swift`, `main.swift`, `Options.swift` and `Formats.swift` end to end — the focused
second pass the backlog's [Provenance](BACKLOG.md#provenance-and-confidence) section asked
for before this work is called done. All seven original findings hold at their cited lines;
that pass also turned up two defects the audit missed, both folded in below.

---

## Contents

- [Why 1.1.0 and not 1.0.1](#why-110-and-not-101)
- [Scope](#scope)
- [The one design decision](#the-one-design-decision) ← *read this before writing code*
- [The commit sequence](#the-commit-sequence)
- [Definition of done](#definition-of-done)
- [Test fixture](#test-fixture)
- [Guardrails — what this release must not touch](#guardrails--what-this-release-must-not-touch)
- [Risk register](#risk-register)

---

## Why 1.1.0 and not 1.0.1

Three changes here alter observable contracts:

- "nothing to import" stops exiting 1 and starts exiting 0
- an unreadable directory starts exiting 3 instead of 0
- `--eject` starts refusing runs it previously performed

A patch release that breaks `fujimm --json && post-process` is the wrong signal, and there is
no CHANGELOG yet through which a user could learn about it. So: minor bump, CHANGELOG.md
created as part of this release, README exit table updated.

**Corollary — break the exit contract once, not twice.** `imp-exit-code-semantics` was filed
for a later release. Doing it separately means breaking scripts twice. It is `S` effort and
it is pulled forward into [Commit 7](#commit-7--exit-contract).

Subsequent milestones in BACKLOG.md shift up one: date correctness → v1.2, README/CI → v1.3,
performance → v1.4, features → v1.5+.

---

## Scope

### In

| Item | Backlog id | Commit |
|---|---|---|
| Fixture-card integration test | [`fix-test-net`](BACKLOG.md#fix-test-net) | 1, 2 |
| Symlinked source re-duplicates every run | [`fix-symlink-size`](BACKLOG.md#fix-symlink-size) | 3 |
| Same name + same size + different bytes = frame discarded | [`fix-silent-drop`](BACKLOG.md#fix-silent-drop) | 4 |
| Re-runs after a collision grow `-N` forever | [`fix-rerun-duplicates`](BACKLOG.md#fix-rerun-duplicates) | 4 |
| `--photos-dir ../..` writes outside `--dest` | [`fix-path-escape`](BACKLOG.md#fix-path-escape) | 5 |
| Weak card guard; `--dest ""` imports into cwd | [`fix-dest-guard`](BACKLOG.md#fix-dest-guard) | 5 |
| Skips and failures invisible under `--json`/`--quiet` | [`fix-scan-failures-invisible`](BACKLOG.md#fix-scan-failures-invisible) | 6 |
| Renamed files' bytes vanish from every total | *new — see below* | 6 |
| Dry-run hardcodes a `-1` suffix | [`fix-readme-claims`](BACKLOG.md#fix-readme-claims) (one row) | 6 |
| "Nothing to import" exits 1 | [`imp-exit-code-semantics`](BACKLOG.md#imp-exit-code-semantics) | 7 |
| `--only photos --eject` ejects a card holding every video | [`fix-eject-gate`](BACKLOG.md#fix-eject-gate) | 8 |
| `-y/--yes` accepted and read nowhere | [`fix-dead-flags`](BACKLOG.md#fix-dead-flags) (half) | 8 |

**`fix-symlink-size` was pulled forward from the next milestone.** The backlog's own
dependency chain says it feeds the identity predicate a correct size, then schedules it a
release later. `Scanner.attributesOfItem` (`Scanner.swift:85`) does not traverse symlinks
while `Copier`'s `open(O_RDONLY)` (`Copier.swift:168`) does, so `item.size` is the link's own
length, the predicate never matches, and every re-run mints another `-N` — violating this
release's own acceptance criterion. It is `S` effort on lines already being edited.

### Two defects found while reading, not in the backlog

**1. Renamed files' bytes are lost from every total.** `CopyOutcome.renamed(to: String)`
(`Copier.swift:11`) carries no byte count, and `main.swift:261-262` accumulates bytes only
for `.copied`/`.overwritten`. So `copiedBytes` — which feeds the throughput rate
(`main.swift:323`) and the JSON `"bytes"` field (`main.swift:308`) — omits every renamed
file's bytes although they were fully written.

This is latent today because collisions get silently skipped. **Fixing `fix-silent-drop`
makes it prominent:** every same-size/different-content pair becomes a `.renamed`, so merging
two bodies onto one destination will report copying 0 bytes at 0 MB/s while writing
gigabytes. Fixed in Commit 6 by carrying bytes on the case.

**2. A concurrency landmine to comment, not fix.** The temp file is named from
`item.filename` (`Copier.swift:95`), not from `dest`, so two sources colliding into one
directory share a temp path. Safe today only because the copy loop is serial and the first
temp is renamed away before the second starts. It becomes live corruption the moment
`imp-copy-overlap` puts N files in flight. Commit 4 adds a comment saying exactly that.

### Out — deferred, deliberately

Date correctness (`fix-sidecar-day`, `fix-tz-abbreviation`, `fix-until-dst`,
`fix-date-format-collapse`, `fix-multicard-order`, `fix-sibling-naming`,
`fix-silent-date-fallback`), AVCHD, orphan `.part` sweeping, `install.sh`, CI, Homebrew, the
`Run` type extraction, any concurrency work, the `Codable` JSON rewrite, and every product
feature.

`--date-format` gets **validation only** in Commit 5, because it is a path-escape vector. Its
day-collapse behaviour is a correctness bug and stays in v1.2.

---

## The one design decision

The two headline bugs pull in opposite directions:

- `fix-silent-drop` says **when unsure, do not skip** — write a new file, because a spurious
  duplicate is recoverable and a dropped frame is not.
- `fix-rerun-duplicates` says **when unsure, do not write** — recognise the existing copy, or
  re-runs grow without bound.

A predicate biased either way fixes one bug by deepening the other. What is needed is not a
safer default but an **accurate** predicate. Today there is exactly one signal:

```swift
// Copier.swift:227-232 — as it stands
private func isAlreadyImported(source: URL, dest: URL, size: Int64) -> Bool {
    guard sameSize(dest, size) else { return false }
    guard options.verify else { return true }        // ← size alone decides
    guard let a = sha256(of: source), let b = sha256(of: dest) else { return false }
    return a == b
}
```

### The predicate

```swift
/// Is `dest` provably the same file as `source`?
///
/// Asymmetric on purpose: `.identical` discards a frame, so it is returned only on
/// positive proof. Anything unknown, unreadable or ambiguous answers `.different`,
/// which costs at worst one redundant `-N` copy.
enum FileIdentity { case identical, different }

func identity(source: URL,
              sourceSize: Int64,
              sourceMTime: Date,
              dest: URL,
              fullHash: Bool) -> FileIdentity
```

Decision order:

1. `stat` the destination, following symlinks. Size differs → `.different`.
2. mtime differs by more than **2 seconds** → `.different`.
3. Content sample: first 64 KB + last 64 KB. Differ → `.different`. Files ≤ 128 KB are
   hashed whole.
4. Under `--verify` (`fullHash: true`), escalate to a full SHA-256 of both sides.
5. Otherwise → `.identical`.

### Why each step is there

**mtime is load-bearing and free.** `Copier` already stamps the source's mtime onto every
copy (`Copier.swift:130-135`), so a genuine re-run has equal mtimes *by construction*.

**The 2-second tolerance is not slop.** exFAT stores modification time at 2-second
granularity. A photographer importing to an exFAT archive drive — normal, for cross-platform
drives — has the destination round the value fujimm wrote. Exact comparison would classify
every such file as different and duplicate the entire archive on the next run.

**Which is exactly why the content sample is mandatory, not an optimisation.** A 2-second
window plus fixed-size uncompressed RAF means a burst at 8–15 fps produces several frames
that are the same size with the same mtime and different content — the precise shape of
`fix-silent-drop`, now inside the tolerance. Step 3 is what makes steps 1–2 safe.

**Head+tail is conclusive in practice.** Two distinct frames always differ within the first
64 KB: EXIF `DateTimeOriginal` and the embedded thumbnail both live there.

**Cost.** 128 KB × 2 per ambiguous file. Re-verifying a 245-file / 20.7 GB import reads about
62 MB, against the ~41 GB `--verify` reads today.

### Prerequisite: `MediaItem` has no mtime

`MediaItem` carries `size` and `date: ResolvedDate`, but `date` is the **capture** date
(EXIF), which for a photo is not the filesystem mtime. `Copier` re-stats the source at
`Copier.swift:130` purely to copy timestamps.

The plumbing is free: `Scanner` already holds the full attributes dictionary at
`Scanner.swift:85` and passes it to the resolver at line 91. Add `mtime: Date` to
`MediaItem` — zero extra I/O. This is why Commit 3 precedes Commit 4.

### One function replaces two

`isAlreadyImported` and `uniqueDestination` become a single walk, which is why these two bugs
are one piece of work:

```swift
enum Placement {
    case existing(URL)   // an identical copy is already here — nothing to do
    case fresh(URL)      // write here
    case exhausted       // 9999 slots used — hard failure, never a silent skip
}

/// Walks dest, dest-1, dest-2, … Returns `.existing` on the first candidate that is
/// provably identical, `.fresh` on the first that does not exist.
func placement(for item: MediaItem, at dest: URL) -> Placement
```

The base path is simply `i = 0`. Two consequences worth stating:

- **`.exhausted` must fail loudly.** Today the 9,999 loop falls out returning the original
  URL (`Copier.swift:255`), the caller compares `alt == dest` (line 84) and reports
  `.skippedIdentical` (line 85) — silently dropping the file. That path becomes
  `.failed("9999 name slots exhausted")`.
- **Delete the comment at `Copier.swift:83.**` *"uniqueDestination also detects an existing
  identical `-1` copy"* is false today. After this change it is true, and the comment should
  describe the walk rather than assert a property.

---

## The commit sequence

Nine commits. Only 3 → 4 is a hard ordering constraint; 5 is independent and can move.

### Commit 1 — test harness, green

Add `Tests/fujimmTests/` and a `.testTarget` in `Package.swift`. **No library split** — a
SwiftPM test target attaches directly to an `executableTarget`, and the orchestration under
test lives in `main.swift`'s top-level statements, so the harness spawns the built binary via
`swift build --show-bin-path`.

Assertions, all passing on `main` today:

1. **Hash the card tree before and after a real run; assert byte-identical.** The README's
   headline promise, mechanically enforced. This is the assertion that would have caught
   `fix-path-escape`.
2. Parse the `--json` line; assert `scanned` / `copied` / `days`.
3. Run twice; assert the second run reports `copied:0`.
4. Assert `--dry-run` planned counts equal the subsequent real run's copied counts.

*Verify:* `swift test` green.

### Commit 2 — test harness, red

Add the two assertions that fail on `main`. This is the bar that defines the release.

5. Same-named, **same-sized**, different-content destination file → a second file appears.
   *(fails — `fix-silent-drop`)*
6. Three runs against a genuine collision → no growth. *(fails — `fix-rerun-duplicates`)*
7. Symlinked source, three runs → exactly one copy. *(fails — `fix-symlink-size`)*

*Verify:* `swift test` reports exactly these three failing.

### Commit 3 — `MediaItem`: correct size, and mtime

`Scanner.swift`. Read `.isRegularFile` and `.fileSize` from the enumerator's prefetched
resource values instead of the second `attributesOfItem` stat; resolve symlinks
(`resolvingSymlinksInPath`) for the stat so the advertised `fujimm --source ~/old-offload`
workflow keeps working; add `.skipsPackageDescendants` so a `.photoslibrary` in a source tree
is not flattened and imported loose; carry `mtime: Date` onto `MediaItem`.

Mechanical. No behaviour change beyond the numbers being correct.

*Verify:* assertion 7 green. Plan for a symlink to a 512 KB file reports `500.0 KB`, not
`115 B`.

### Commit 4 — the identity predicate

`Copier.swift`. Implement `FileIdentity` and `Placement` as specified above. `isAlreadyImported`
and `uniqueDestination` both collapse into `placement(for:at:)`. `.exhausted` becomes
`.failed`. Fix the comment at line 83. Add the temp-name concurrency comment at line 95.

The dry-run branch (`Copier.swift:45-61`) calls the same function, so dry run and real run
cannot diverge by construction.

*Verify:* assertions 5 and 6 green. Backlog reproductions #1 and #2 flip.

### Commit 5 — destination containment

> **Revised after measurement.** The prescription originally written here was wrong in two
> ways and incomplete in a third. What follows replaces it; every claim below was verified by
> running code on this machine (macOS 26, Swift 6.3.3).

`fix-path-escape` and `fix-dest-guard` are the same problem at two altitudes, so they share
one helper.

**What the original spec got wrong.**

1. *"Compare symlink-resolved paths"* — `URL.resolvingSymlinksInPath()` is **all-or-nothing**.
   If the full path does not exist it resolves nothing, not even leading components that exist
   and are themselves symlinks. A destination that does not exist yet is the normal case for a
   first import, so that guard would have done nothing on the path it was written to protect.
   It also maps `/private/tmp` → `/tmp` while `realpath` maps `/tmp` → `/private/tmp`, so
   mixing the two guarantees a mismatch under `/tmp` and `/var/folders` — where
   `NSTemporaryDirectory()`, and therefore the test suite, lives.
2. *"Case-insensitive comparison"* — unnecessary, and lowercasing would be wrong in both
   directions (it equates distinct files on a case-sensitive volume and ignores Unicode
   normalisation). `realpath(3)` returns the on-disk spelling of every component, so its
   output compares correctly with `==` on case-sensitive and case-insensitive volumes alike.
3. **Missing:** `FileManager.createDirectory(withIntermediateDirectories: true)` **follows a
   symlink out of the destination root.** Demonstrated: a symlink at `<dest>/broken` pointing
   outside, plus a request for `<dest>/broken/sub`, writes outside `<dest>`. A containment
   check placed before the write does not stop this, because the write itself does the
   escaping.

**What to build.**

- **A `PathSafety` helper** (new file, `Sources/fujimm/PathSafety.swift`), zero dependencies:
  - `canonical(_:)` — `realpath(3)`. Resolves symlinks, `..`, `.`, and case. Requires existence.
  - `deepestExisting(_:)` — walks up until `canonical` succeeds, returning the resolved
    ancestor plus the not-yet-existing tail. Terminate on `parent.path == url.path`, which is
    a fixed point for paths ending in `..` and so fails those closed.
  - `path(_:isInsideOrEqualTo:)` — **fails closed.** Compares component arrays of canonical
    paths, never `hasPrefix` (`"/a/bc".hasPrefix("/a/b")` is `true`), then confirms with
    `st_dev`+`st_ino` identity of the ancestor taken at the root's depth. Any doubt → `false`
    → refuse the item.
  - `onSameVolume(_:_:)` — **fails open**, returning `Bool?`. Primary signal
    `.volumeIdentifierKey` on the deepest existing ancestor (it throws for non-existent paths,
    and it correctly treats the firmlinked system/data pair as one volume); fallback
    `statfs().f_mntonname`; `nil` when undeterminable.
  - `createDirectoryChain(root:tail:)` — `mkdir(2)` one component at a time, requiring `lstat`
    to report a real directory on `EEXIST`. Replaces `createDirectory(withIntermediateDirectories:)`
    on the copy path.
- **Parse time** (`Options.swift`): reject a bucket name that is empty, `.`, `..`, or contains
  `/`. Reject an empty or whitespace-only `--dest`. For `--date-format`, format a date and
  reject the **output** if any `/`-separated component is `..` — not the pattern, because
  `yyyy'/../'MM` smuggles `..` through a quoted literal and produces `2026/../06`.
- **Card guard** (`main.swift:105-113`): `PathSafety.onSameVolume(...) == true`. The `== true`
  is deliberate: `nil` allows the import rather than blocking a legitimate one.
- **Before the write** (`Copier.swift:42`): assert containment, and add `O_NOFOLLOW` to the
  temp-file `open` to close the check-to-open window.

**What must keep working.** `--date-format 'yyyy/MM/dd'` produces components
`["2026","06","15"]` — no `..` — so the documented nested-folder behaviour survives a rule
that rejects only `..` components. Measured, not assumed. A rule rejecting `/` would break it.

**Not a threat.** A filename read off a card cannot contain `/` or be `..`: the filesystem
refuses to create either. Verified. The filename needs no sanitising.

*Verify:* reproduction #3 flips — `--photos-dir '../../escape/PWNED'` exits 2 instead of
writing outside `--dest`. Nested date format still nests. The symlink-in-the-path escape is
refused.

### Commit 6 — reporting truth

- Thread `unreadable` and `unknownExtensions` into the JSON summary; add
  `"failures":[{path,reason}]`.
- Emit the failure list on **stderr regardless of `--quiet`** — `--help` already describes
  `--quiet` as "errors only".
- Add `"schemaVersion": 1`. One line, and it is what makes any future JSON change
  announceable. The `Codable` rewrite and the `--list` shape unification stay deferred.
- `case renamed(to: String, bytes: Int64)`; include those bytes in `copiedBytes`, the rate and
  the JSON `"bytes"` field.
- `main.swift:317`: print the real suffix from the record instead of the hardcoded `-1`.

*Verify:* reproductions #8 and #12 flip. A run that renames files reports non-zero bytes.

### Commit 7 — exit contract

Isolated in its own commit because it is the breaking change, and it should be reviewable and
revertible on its own.

- "Nothing to import" → exit **0**. Keep exit 1 for "no card found". Add `--fail-on-empty`
  for anyone relying on the old behaviour.
- A non-empty `unreadable` set → exit **3**.
- Update the README exit table.

*Verify:* reproduction #11 flips. `fujimm --json && echo ok` prints `ok` on a fully-imported
card.

### Commit 8 — eject gate

`--eject` currently fires on `failedCount == 0 && !wasInterrupted` (`main.swift:342`), ignoring
`--only`, `--since`/`--until`, `skippedByFilter`, `unreadable`, and extensions skipped for want
of `--other`.

Reach `Volumes.eject` only when the run can prove every media file on the card is now at the
destination. Otherwise print what was left and decline. Give `-y/--yes` the job of overriding
that refusal — which retires the dead flag rather than deleting it.

*Verify:* `fujimm --only photos --eject` on a card with videos declines and explains.
Reproduction #16 flips.

### Commit 9 — CHANGELOG and version

Create `CHANGELOG.md` with a 1.1.0 entry that states plainly that **v1.0.0 could silently
discard a frame, and anyone who imported two cards into one day folder should re-import and
compare counts.** That is the entire reason this file exists.

Bump `Options.version` to `1.1.0`, tag `v1.1.0`, and add
`.claude/settings.local.json` to `.gitignore` — it is currently neither tracked nor ignored.

---

## Definition of done

The release is done when all of the following hold.

**Tests.** `swift test` green, including all seven assertions from Commits 1–2.

**Reproductions.** These entries in [BACKLOG.md's appendix](BACKLOG.md#appendix-reproductions)
flip from *Observed* to *Expected*:

| # | Was | Now |
|---|---|---|
| 1 | Re-run ×3 → `-1`, `-2`, `-3` | "already there" after the first |
| 2 | Same size, different bytes → **frame lost**, exit 0 | `DSCF0001-1.JPG` created |
| 3 | `--photos-dir '../../escape/PWNED'` writes outside `--dest` | Argument rejected, exit 2 |
| 6 | Symlinked source → plan says `115 B`, 3 runs → 3 copies | `500.0 KB`, 1 copy |
| 8 | `--json` silent about unrecognised files | Reported |
| 11 | Empty card exits 1 | Exits 0 |
| 12 | Dry run says `-1` when reality is `-4` | Says `-4` |
| 16 | `-y/--yes` read nowhere | Overrides the eject refusal |

Reproductions 4, 5, 7, 9, 10, 13, 14, 15 remain open by design — they are v1.2 and later.

**Additional acceptance criteria** beyond the backlog's original four, each covering a hole
the original set would have let through:

- A symlinked source imports exactly once across three consecutive runs.
- `--dry-run`'s reported collision names equal the real run's.
- Summary and JSON `bytes` equal the bytes actually written, **including renames**.
- A destination on an **exFAT** volume does not re-duplicate on the second run. *(This is the
  mtime-granularity case the predicate's 2-second tolerance exists for. It needs a real exFAT
  volume or a disk image — `hdiutil create -fs exFAT`.)*

**Docs.** CHANGELOG.md exists and names the data-loss bug. README exit table matches the code.

---

## Test fixture

No camera, no SD card, no committed binary fixtures. Built at test time:

```
card/
  DCIM/
    100_FUJI/
      DSCF0001.JPG      synthesized JPEG carrying EXIF DateTimeOriginal (day A)
      DSCF0002.RAF      /dev/urandom, touch -t to day B
      DSCF0003.MOV      /dev/urandom, touch -t to day B
      ._DSCF0001.JPG    AppleDouble stub    → Formats.isJunk
      .DS_Store                             → Formats.isJunk
    101_FUJI/
      DSCF0001.JPG      SAME NAME, SAME SIZE, different bytes  → the fix-silent-drop case
      DSCF0004.RAF      same size + mtime within 2s, different bytes → the burst case
    102_FUJI/           chmod 000                              → the unreadable path
  FFDB/                 empty                                  → ignoredDirectories
  MISC/                 empty                                  → ignoredDirectories
```

Plus, in a separate `--source` tree: a symlink to a 512 KB file, and a `.photoslibrary`
bundle to exercise `.skipsPackageDescendants`.

A ~793-byte JPEG with a real `DateTimeOriginal` can be synthesized with
`CGImageDestinationAddImage`, so the EXIF path is covered with **zero checked-in binaries**.

**One trap for whoever writes the harness:** `Formats.isJunk` (`Formats.swift:75`) treats
*any* dotfile as junk, so an orphan `.fujimm-*.part` is absorbed into `skippedJunk` and is
invisible to a scan. Assert on the filesystem directly, never through fujimm's own reporting.

---

## Guardrails — what this release must not touch

Every one of these is a real, filed improvement. Each is also a way for this release to stop
being reviewable.

- **No `Run` type extraction.** Deferred to v1.4. The harness spawns the binary; the
  assertions survive that refactor unchanged.
- **No concurrency.** Not in the scan, not in the copy loop. The predicate is the only change
  to the data path this release should contain.
- **No `Options` split**, no `Plan` type, no `Codable` JSON rewrite.
- **No date-resolution changes** beyond plumbing mtime onto `MediaItem`.
- **No new user-facing capability.** `--fail-on-empty` is the single new flag, and it exists
  only to preserve a behaviour this release removes.

---

## Risk register

| Risk | Mitigation |
|---|---|
| **The predicate is the one change that can lose data if it is wrong.** | Commits 1–2 land the red bar first, so the fix is judged by tests written before it. `.identical` requires positive proof. `.exhausted` fails loudly instead of skipping. |
| exFAT destination rounds mtime → mass re-duplication | 2-second tolerance, plus the content sample that makes the tolerance safe. Explicitly in the acceptance criteria, tested against a real exFAT image. |
| Containment assert breaks legitimate nested `--date-format 'yyyy/MM/dd'` | Reject only `..` components, never `/`. Dedicated test. |
| Eject gate reads as a regression to anyone pairing `--only` with `--eject` | Refuse with an explicit message naming what was left, and an explicit `-y` override. |
| Exit-code change breaks someone's script | Minor version bump, isolated commit, CHANGELOG entry, README exit table, `--fail-on-empty` escape hatch. |
| Scope creep — every file touched here has three other filed bugs in it | The guardrail list above. Anything not in [Scope](#scope) goes to BACKLOG.md, not into this branch. |

---

*Plan derived from BACKLOG.md and a direct read of the v1.0.0 source. Where the two disagree —
`fix-symlink-size`'s release, the version number, and the two defects in
[Scope](#scope) — this document is the later judgement and wins.*
