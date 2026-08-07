# fujimm — backlog and roadmap

Working document for `fujimm` at v1.0.0 (1,478 lines of Swift, 8 files, one commit,
no tests, no CI). It sorts what to work on into four types — **fixes**, **improvements**,
**technologies**, **product features** — and sequences them into releases.

Nothing here has been applied. This is a plan, not a changelog.

---

## Contents

- [How to read this](#how-to-read-this)
- [Provenance and confidence](#provenance-and-confidence)
- [The roadmap](#the-roadmap) ← *start here*
- [Fixes](#fixes)
- [Improvements](#improvements)
- [Technologies](#technologies)
- [Product features](#product-features)
- [Won't do](#wont-do)
- [Dependency chains](#dependency-chains)
- [Appendix: reproductions](#appendix-reproductions)

---

## How to read this

Every item carries the same header:

| Field | Meaning |
|---|---|
| **Impact** | `critical` loses or corrupts a photograph, or falsifies a safety promise · `high` wrong data or wrong trust signal · `medium` friction · `low` polish |
| **Effort** | `S` under a day · `M` a few days · `L` a week or two · `XL` bigger |
| **Verified** | `reproduced` — run against a real build in this session · `agent-reproduced` — an auditor reported a reproduction not independently re-run · `code-read` — established by reading the source only |

Impact is about the *photographer*, not the code. A three-line bug that silently drops
a frame outranks a hundred-line refactor.

---

## Provenance and confidence

Findings came from seven parallel auditors, each given one lens (copy-path correctness,
scan/date correctness, CLI surface, performance, platform/tooling, product, hygiene/safety),
plus a lead pass. **Three auditors — copy-path correctness, performance, and CLI
surface — died mid-run on a session limit, as did the adversarial refutation stage and
the sequencing judge.**

Consequences you should know about before trusting this document:

1. **No finding was independently refuted.** The refutation stage never ran. To
   compensate, every `critical` and `high` item was re-tested by hand against a real
   build (`swift build`, Swift 6.3.3, macOS 26). Those are marked `reproduced` and are
   the ones to trust. Items marked `agent-reproduced` are plausible and cited but carry
   one layer less scrutiny.
2. **`Copier.swift`, `Term.swift` and the performance story are thinner than the rest.**
   The items below covering them come from the lead pass, not a dedicated auditor.
   `Copier.swift` in particular — the file that actually touches your photographs —
   deserves a second, focused correctness pass before the v1.1.0 work is called done.
   **That pass has since been done** — see [RELEASE-1.1.0.md](RELEASE-1.1.0.md), which
   confirms every finding below and adds two the auditors missed.
3. **One auditor corrected a lead-pass assumption**, and the correction is load-bearing:
   a SwiftPM `.testTarget` attaches to an `executableTarget` and `@testable import fujimm`
   reaches every type. A `fujimmCore` library split is **not** a prerequisite for testing.
   See [`tech-run-type`](#tech-run-type).

---

## The roadmap

Five releases. The ordering principle is that fujimm's only real asset is that people
trust it with irreplaceable files, so **everything that falsifies a promise ships before
anything that adds a capability.**

### v1.1.0 — "it does not lose photographs" · ~1 week

> **This release is now planned in detail in [RELEASE-1.1.0.md](RELEASE-1.1.0.md)**, which
> supersedes this table. That plan pulls [`fix-symlink-size`](#fix-symlink-size) and
> [`imp-exit-code-semantics`](#imp-exit-code-semantics) forward, adds two defects found by a
> direct read of the source, and takes a minor version rather than a patch because the exit
> contract changes.

The tool currently has two paths that silently discard a frame and one that writes
outside the destination. Nothing else matters until these are closed.

| Item | Why now |
|---|---|
| [`fix-test-net`](#fix-test-net) | **First.** A subprocess-driven fixture-card test works today with zero refactor. Every fix below needs a regression net, and one of the assertions *is* the read-only promise. |
| [`fix-silent-drop`](#fix-silent-drop) | Same name + same size + different bytes = the frame is silently discarded, exit 0. |
| [`fix-path-escape`](#fix-path-escape) | `--photos-dir ../..` writes outside `--dest`, including back onto the card, while printing "The card was not modified." |
| [`fix-rerun-duplicates`](#fix-rerun-duplicates) | Every re-run after a collision adds another `-N` copy, forever. |
| [`fix-scan-failures-invisible`](#fix-scan-failures-invisible) | An unreadable DCIM folder produces `{"status":"ok"}` and exit 0. |
| [`fix-eject-gate`](#fix-eject-gate) | `--only photos --eject` ejects a card that still holds every video. |
| [`fix-dest-guard`](#fix-dest-guard) | `--dest ""` imports into the current directory. |

**Exit criteria:** the fixture-card test asserts (a) the card tree is byte-identical
before and after a real run, (b) a same-size/different-content collision produces a
second file rather than a skip, (c) three consecutive re-runs produce zero new files,
(d) a bad `--photos-dir` exits 2. All four fail on `main` today.

### v1.2 — "the day folder is the right day" · ~1 week

Six ways a file lands in the wrong folder, or a filter silently does the wrong thing.
None loses data; all of them quietly make the output wrong.

[`fix-sidecar-day`](#fix-sidecar-day) · [`fix-tz-abbreviation`](#fix-tz-abbreviation) ·
[`fix-until-dst`](#fix-until-dst) · [`fix-symlink-size`](#fix-symlink-size) ·
[`fix-date-format-collapse`](#fix-date-format-collapse) ·
[`fix-multicard-order`](#fix-multicard-order) · [`fix-sibling-naming`](#fix-sibling-naming) ·
[`fix-silent-date-fallback`](#fix-silent-date-fallback)

**Exit criteria:** `--tz EST` and `--tz America/New_York` agree or the former is rejected;
a sidecar and its RAF are always in the same folder; `--date-format ''` exits 2.

### v1.3 — "the README is true, and CI proves it" · ~3–4 days

Honesty and infrastructure. Cheap, and it stops the drift from getting worse.

[`fix-readme-claims`](#fix-readme-claims) · [`fix-dead-flags`](#fix-dead-flags) ·
[`fix-avchd`](#fix-avchd) · [`fix-orphan-parts`](#fix-orphan-parts) ·
[`fix-install-sh`](#fix-install-sh) · [`tech-ci`](#tech-ci) ·
[`tech-dead-frameworks`](#tech-dead-frameworks) · [`tech-version-tag`](#tech-version-tag) ·
[`imp-trademark-line`](#imp-trademark-line)

**Exit criteria:** CI green on push; a CI job fails if `Options.version` disagrees with
the tag; every flag `OptionsParser` accepts appears in `--help`.

### v1.4 — "it is fast, and the output is honest about it" · ~1 week

Now that there is a test net, the copy and scan paths can be touched.

[`tech-run-type`](#tech-run-type) → [`imp-parallel-scan`](#imp-parallel-scan) ·
[`imp-copy-overlap`](#imp-copy-overlap) · [`imp-verify-double-hash`](#imp-verify-double-hash) ·
[`imp-redundant-stat`](#imp-redundant-stat) · [`imp-progress-tty`](#imp-progress-tty) ·
[`imp-eta-throttle`](#imp-eta-throttle) · [`imp-exit-code-semantics`](#imp-exit-code-semantics) ·
[`imp-json-contract`](#imp-json-contract) · [`tech-swift6`](#tech-swift6)

### v1.5+ — "the thing only this tool can do"

Features, in the order I would build them.

1. [`feat-stacks`](#feat-stacks) — the unit of import becomes the frame, not the file.
   Unlocks `--only raw`, fixes the sidecar class of bug at the root, prerequisite for
   renaming and for `--newest`.
2. [`feat-manifest-audit`](#feat-manifest-audit) — a receipt with checksums, plus
   `--audit`. This is the trust product, and the honest answer to "can I format the card?"
3. [`feat-multi-dest`](#feat-multi-dest) — read the card once, write two copies.
4. [`feat-film-sim`](#feat-film-sim) — the differentiator, and it is nearly free.
5. Then: [`feat-last-day`](#feat-last-day), [`feat-foreign-raw`](#feat-foreign-raw),
   [`feat-session-grouping`](#feat-session-grouping), [`feat-shoot-log`](#feat-shoot-log),
   [`feat-only-new`](#feat-only-new), [`feat-hooks`](#feat-hooks),
   [`feat-log-file`](#feat-log-file), [`feat-contact-sheet`](#feat-contact-sheet),
   [`feat-rename`](#feat-rename).

### The three things to start on, in order

1. **[`fix-test-net`](#fix-test-net)** — a subprocess fixture-card test. It needs no
   refactor, it takes an afternoon, and it turns the README's headline promise into an
   assertion. Everything else is safer after it exists.
2. **[`fix-silent-drop`](#fix-silent-drop)** — the only bug here that destroys a
   photograph with an exit code of 0.
3. **[`fix-path-escape`](#fix-path-escape)** — the only bug that can make the tool write
   to the card it promises never to touch.

### Biggest risk to the project

Not any single bug — it is that **the safety claims are structural in the README and
procedural in the code, with nothing in between to hold them**. "The card is read-only,
structurally" is true of the I/O (`open(..., O_RDONLY)`, no `unlink`/`rename` of any
source) and false of the composed destination path, which can be walked back onto the
card by an unvalidated flag. "Re-running costs nothing" is true in the happy path and
false in three separate collision paths. There is no test target, so every one of these
promises is currently held by nothing but the author's memory. A single test target and
one fixture card converts the whole class from hope into CI, which is why it is the
first item in the plan rather than a maturity milestone somewhere in v2.

---

## Fixes

Defects: the tool does something wrong today.

---

### `fix-silent-drop`
**Stop treating same-name + same-size as "already imported"**

`Impact: critical` · `Effort: S` · `Verified: reproduced`

`Copier.isAlreadyImported` returns `true` on a size match alone unless `--verify` is
passed. The copy path then returns `.skippedIdentical`, `main.swift` counts it under
"already there", and the process exits 0. **The frame is never copied, never renamed,
and never mentioned.**

This is not theoretical for Fujifilm specifically. Counters wrap at `DSCF9999` and
restart; a second body or a second card reuses the same `DSCF####` names; and
uncompressed RAF is a **fixed byte size for a given body**, so same-name/same-size/
different-content is the *normal* case when two cards merge into one day folder.

```
Sources/fujimm/Copier.swift:227-232   isAlreadyImported — guard sameSize else false; guard verify else true
Sources/fujimm/Copier.swift:234-238   sameSize compares .size only
Sources/fujimm/Copier.swift:75-78     the skip branch
Sources/fujimm/main.swift:288,324     counted as "already there"
README.md:130-131                     "An existing destination file is never clobbered."
```

**Reproduced.** Source and destination `DSCF0001.JPG`, both 5,000 bytes, different
content. Run reports `already there 1`, exits 0, and the destination file's SHA-256 is
unchanged — the real photo was silently discarded. Adding `--verify` produces the
correct `-1` file, confirming the size-only path is the cause.

**Fix.** Compare `(size, modificationDate)` — fujimm already stamps the source mtime onto
every copy — and fall back to a head+tail sample hash when both match. Anything not
*provably* identical must go down `uniqueDestination`, never the skip path. Whatever the
heuristic, the skip decision must never be able to drop bytes with exit 0.

**Risk.** Comparing mtime will reclassify some genuinely identical files as collisions if
the destination copy's timestamps were altered by another tool, producing spurious `-1`
duplicates. Mitigate with the content sample rather than assuming difference.

---

### `fix-path-escape`
**Validate `--photos-dir` / `--videos-dir` / `--other-dir` / `--date-format`**

`Impact: critical` · `Effort: S` · `Verified: reproduced`

`Scanner.destinationPath` interpolates the three bucket names and the formatted day
straight into a relative path; `Copier.copy` does
`root.appendingPathComponent(item.relativeDestination)`. `appendingPathComponent` does
not normalise, but `createDirectory(withIntermediateDirectories:)` and `open(2)` resolve
`..` in the kernel — so any component containing `..` walks out of the destination root.

The card-safety guard in `main.swift` only compares `options.destination` against the
card path. It never sees the composed per-item path. So `--photos-dir '../../<card>/DCIM/…'`
writes files **onto the card** while the summary still prints *"The card was not
modified."* That falsifies the tool's headline promise.

`--date-format` reaches the same place: `DateFormatter` passes `.` and `/` through as
literals, so `--date-format '../..'` needs no quoting at all.

```
Sources/fujimm/Scanner.swift:140-149  destinationPath interpolation
Sources/fujimm/Copier.swift:42        root.appendingPathComponent(relativeDestination)
Sources/fujimm/main.swift:105-113     the guard, which only sees options.destination
Sources/fujimm/main.swift:337         "The card was not modified."
README.md:121-122                     "no code path … writes to … a file on the card"
```

**Reproduced.** `fujimm --dest <D>/inner --photos-dir '../../escape/PWNED'` created
`<D>/escape/PWNED/DSCF0001.JPG` — two levels outside the requested destination — and
exited 0.

**Fix.** Reject any bucket name that is empty, `.`, `..`, or contains `/`. After
formatting the day, reject any resulting path component equal to `..`. Then, immediately
before opening, assert that
`dest.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/")`
and fail the item otherwise. The belt-and-braces assert matters because it also catches
anything a future flag introduces.

**Risk.** Someone deliberately using `--photos-dir ../Raw` to hoist one level breaks.
That is worth breaking — make it a clear error, not a silent clamp. Keep the documented
`--date-format 'yyyy/MM/dd'` nested-folder behaviour working; only `..` components are
rejected.

---

### `fix-rerun-duplicates`
**Make `uniqueDestination` recognise an existing identical `-N` copy**

`Impact: high` · `Effort: S` · `Verified: reproduced`

`uniqueDestination` walks `base-1`, `base-2`, … and returns the first path that does not
exist. It never compares content or size against the candidates it skips. So a file that
collided once and landed as `DSCF0001-1.JPG` collides again next run and lands as `-2`,
then `-3`, forever.

The inline comment at `Copier.swift:84` asserts that *"uniqueDestination also detects an
existing identical `-1` copy"*. It does not. The `if alt == dest { return .skippedIdentical }`
guard it protects is unreachable except when all 9,999 slots are full — in which case
reporting `.skippedIdentical` **silently drops the file**.

`--verify` makes this *worse*, not better: it correctly detects the content difference,
so it duplicates more files rather than fewer.

```
Sources/fujimm/Copier.swift:242-256   uniqueDestination — existence check only
Sources/fujimm/Copier.swift:83-88     the caller and the incorrect comment
Sources/fujimm/Copier.swift:250-255   9999 exhaustion returns url → caller maps to .skippedIdentical
README.md:128-129                     "re-running costs nothing"
```

**Reproduced.** Four consecutive runs against an unchanged source produced
`DSCF0001.JPG`, `-1`, `-2`, `-3` — three byte-identical copies of the same frame.

**Fix.** Have `uniqueDestination` return an "already present as `base-N`" result when a
numbered sibling matches the source, using the same identity predicate as
[`fix-silent-drop`](#fix-silent-drop). Fail loudly rather than returning
`.skippedIdentical` when the 9,999 loop is exhausted.

**Risk.** A stat per candidate plus a sampled read when sizes match — negligible next to
the copy. If the predicate is too strict the user gets one extra duplicate, i.e. exactly
today's behaviour, so the change cannot make things worse.

---

### `fix-scan-failures-invisible`
**Report skips and failures in every output mode; exit non-zero for them**

`Impact: critical` · `Effort: M` · `Verified: reproduced`

Everything fujimm knows about what it did *not* copy is printed inside a single
`if !options.quiet && !options.json` block, so all of it vanishes under `--json` and
`--quiet`. Worse: `Scanner`'s enumerator `errorHandler` collects unreadable directories
into `ScanResult.unreadable` and keeps walking, but those entries never become
`MediaItem`s, never become `CopyRecord`s, never increment `failedCount`, and therefore
**never affect the exit code**. An entire unreadable DCIM subfolder yields
`{"status":"ok"}` and exit 0.

The JSON summary has no field for `unreadable`, `unknownExtensions` or `skippedByFilter`
at all. `--quiet` suppresses even the per-file failure list, despite `--help` describing
it as "Errors only".

A photographer scripting `fujimm --json --eject` gets a success signal from a run that
left photos on the card.

```
Sources/fujimm/Scanner.swift:37-45    errorHandler appends and returns true
Sources/fujimm/main.swift:150         the !quiet && !json gate around the whole plan block
Sources/fujimm/main.swift:191-199     the only place unknownExtensions/unreadable are printed
Sources/fujimm/main.swift:300-310     JSON summary has no field for any of them
Sources/fujimm/main.swift:353         exit code derives from failedCount only
README.md:135-136                     "Unrecognised extensions are *reported*, never silently dropped."
```

**Reproduced.** A card with one `.XYZ` file: text mode prints
`not importing unrecognised types: XYZ ×1`; `--json` prints a clean `{"status":"ok",…}`
with `"scanned":1` and no mention; `--quiet` prints nothing.

**Fix.** Thread `unreadable` and `unknownExtensions` into the JSON object; emit the
failure list on stderr regardless of `--quiet`; add a `"failures":[{path,reason}]` array;
make a non-empty `unreadable` set produce exit 3.

**Risk.** Changing the exit contract belongs in a minor bump with a CHANGELOG entry.
Adding JSON fields is additive and safe.

---

### `fix-eject-gate`
**Refuse `--eject` when anything was left on the card**

`Impact: high` · `Effort: S` · `Verified: code-read`

The eject decision is gated only on `failedCount == 0 && !wasInterrupted`. It does not
consider `--only`, `--since`/`--until`, `ScanResult.skippedByFilter`,
`ScanResult.unreadable`, or unrecognised extensions skipped because `--other` was absent.

So `fujimm --only photos --eject` deliberately leaves every video on the card and then
ejects it. Eject is the step immediately before a photographer formats the card in
camera, which makes it the highest-consequence decision in the tool.

```
Sources/fujimm/main.swift:342         if options.eject && !options.dryRun && failedCount == 0 && !wasInterrupted
Sources/fujimm/Volumes.swift:140-153  shells out to /usr/sbin/diskutil eject
Sources/fujimm/Scanner.swift:17       skippedByFilter — incremented in four places, read in none
```

**Fix.** Reach `Volumes.eject` only when the run can prove every media file on the card
is now at the destination. Otherwise print what was left and decline, with an explicit
override. This is the natural job for the `-y/--yes` flag that
[`fix-dead-flags`](#fix-dead-flags) would otherwise delete.

**Risk.** Users who habitually pair `--only` with `--eject` will read the refusal as a
regression. The README frames the tool around not losing photographs, so erring toward
refusal is defensible.

---

### `fix-dest-guard`
**Resolve symlinks and volume identity in the don't-import-into-the-card guard; reject an empty `--dest`**

`Impact: high` · `Effort: S` · `Verified: agent-reproduced`

The read-only audit of the *source* side is clean — every source access is a read
(`O_RDONLY`, `FileHandle(forReadingFrom:)`, `attributesOfItem`, `enumerator`,
`CGImageSourceCreateWithURL`, `AVURLAsset`). The thing that can turn fujimm into a writer
is the destination, and the guard protecting it is weak in three ways:

- `standardizedFileURL` does **not** resolve symlinks, so a symlink into the card passes.
- The comparison is case-sensitive while both APFS and exFAT default to case-insensitive.
- `--dest ""` parses to `URL(fileURLWithPath: "")`, which Foundation resolves to the
  current working directory. A script with an unset `$DEST` silently imports 20 GB into
  the cwd.

```
Sources/fujimm/main.swift:105-113     dest == src || dest.hasPrefix(src + "/")
Sources/fujimm/Options.swift:63-66    --dest parsing, no empty check
```

**Fix.** Compare symlink-resolved paths, plus a volume-identity check
(`URLResourceKey.volumeIdentifierKey` on the destination's nearest existing ancestor
versus the card's volume). Make an empty or whitespace-only `--dest` an
`OptionsError.usage`. Volume identity is the robust half and should be primary; keep the
path prefix as a cheap fallback.

**Worth one README sentence too:** `diskutil eject` does cause the OS to flush and
unmount the card, so "no code path writes to the card" is true of fujimm's own I/O but
not of the eject handshake it invokes.

---

### `fix-sidecar-day`
**A sidecar inherits its sibling's bucket but not its day**

`Impact: high` · `Effort: M` · `Verified: reproduced`

`Scanner` resolves a sidecar's `MediaKind` from `siblingKind`, so a `.XMP` correctly goes
to `Photos/`. But the *day* is then computed independently from the sidecar's own bytes.
`photoDate` cannot parse an XMP, so it falls through to `filesystemDate` and uses the
sidecar's mtime — which is whenever the edit was made.

A RAF shot on 15 June whose XMP Lightroom touched today lands in a **completely different
day folder** from the file it describes. The README says sidecars "follow whichever file
shares their basename", which a reader takes to mean the file, not merely the bucket.

```
Sources/fujimm/Scanner.swift:67-70,91,126-138
Sources/fujimm/DateResolver.swift:62,68,121-130
README.md:144
```

**Reproduced.** `DSCF0002.RAF` (mtime 2026-06-15) and `DSCF0002.XMP` (mtime 2026-08-07)
in one folder produced `2026-06-15/Photos/DSCF0002.RAF` and
`2026-08-07/Photos/DSCF0002.XMP`.

**Fix.** Carry the sibling's `ResolvedDate`, not just its kind: have `siblingKind` return
the sibling URL, resolve that URL's date, reuse it. Cache per basename within a directory
to avoid re-reading the RAF. The general form of this is [`feat-stacks`](#feat-stacks),
which fixes the whole class — but the bug is worth closing on its own first.

---

### `fix-tz-abbreviation`
**`--tz EST` becomes a fixed UTC−5 zone with no DST rules**

`Impact: high` · `Effort: S` · `Verified: reproduced`

`Options` falls back to `TimeZone(abbreviation:)` when the identifier lookup fails. Some
abbreviations map to real regions; `EST` and `JST` resolve to **fixed-offset** zones whose
`nextDaylightSavingTimeTransition` is `nil`. A New York photographer typing the obvious
`--tz EST` gets a permanent UTC−5 day boundary, so anything shot between 00:00 and 01:00
local during the eight months of EDT is filed one day early.

**Reproduced.** Same file, July: `--tz EST` → `2026-07-03`; `--tz America/New_York` →
`2026-07-04`.

The same item covers the `--since`/`--until` reparse loop, which rescans raw argv for the
literal tokens `--since`/`--until` with no notion of which tokens are option *values* —
so whether the loop runs changes how the rest of the command line parses.

```
Sources/fujimm/Options.swift:51-55,109-114,126-139
```

**Fix.** Either reject abbreviations outright or accept them with a warning that the zone
has no DST rules. Then delete the reparse loop entirely: first pass extracts only
`--timezone`/`--tz`, second pass parses everything else with the resolved zone in hand.

---

### `fix-until-dst`
**`--until` adds a hardcoded 86,399 s, wrong on every DST transition day**

`Impact: high` · `Effort: S` · `Verified: code-read`

`OptionsParser.parseDay` computes end-of-day as midnight + `24*3600-1`. A DST transition
day is 23 or 25 hours long, so the bound lands on the wrong side.

- Spring forward: `--until 2026-03-29 --tz Europe/Paris` resolves to
  `2026-03-30 00:59:59` local, pulling in files shot in the first hour of a day the user
  explicitly excluded — which then land in a folder they excluded.
- Fall back: `--until 2026-10-25` resolves to `2026-10-25 22:59:59`, dropping everything
  shot in the last hour of the requested day.

```
Sources/fujimm/Options.swift:147-158
Sources/fujimm/Scanner.swift:93-100
```

**Fix.** Use `Calendar` with the chosen `timeZone`: `startOfDay` for `--since`, and
`date(byAdding: .day, value: 1, to: startOfDay)` for `--until` with a half-open
`inst >= end` exclusion.

**While you are there:** `ResolvedDate.instant` is `Optional`, and a `nil` instant makes
*both* filters silently **include** the item — the opposite of what a date filter should
do. Either make it non-optional (it already is in practice) or exclude on `nil`.

---

### `fix-symlink-size`
**Consult `.isRegularFileKey`; a symlinked source re-duplicates every run**

`Impact: high` · `Effort: S` · `Verified: reproduced`

`Scanner` asks the enumerator for `.isRegularFileKey` and `.fileSizeKey` but **reads
neither** — the only resource value consulted is `.isDirectoryKey`, and size comes from a
second full stat via `attributesOfItem`, which does not traverse symlinks. Meanwhile
`streamCopy`'s `open(src.path, O_RDONLY)` *does* follow the link.

So `MediaItem.size` is the link's own byte length, which poisons three things: the plan
shown to the user, the free-space check, and — worst — `isAlreadyImported`, which
compares the destination's real size against the link's size, never matches, and mints a
fresh `-1`, `-2`, `-3` on every re-run.

This is reachable through the advertised `fujimm --source ~/old-offload` workflow, where
rsync and backup trees routinely contain symlinks.

**Reproduced.** A symlink to a 512 KB file: the plan reported `1 files, 115 B`; three runs
produced `DSCF0004.JPG`, `-1`, `-2`.

The same unused-key gap means `options: []` leaves `.skipsPackageDescendants` off, so the
walker descends into bundles — a `.photoslibrary` inside a `--source` tree is flattened
and its internals imported as loose photos.

```
Sources/fujimm/Scanner.swift:39,51,85-89
Sources/fujimm/Copier.swift:168,227-238
```

**Fix.** Read `isRegularFile` and `fileSize` from the enumerator's prefetched values; add
`.skipsPackageDescendants`. Prefer resolving the link (`resolvingSymlinksInPath`) for the
stat over skipping it outright, so the advertised `--source` workflow keeps working.

---

### `fix-date-format-collapse`
**An empty or malformed `--date-format` silently collapses every day into one folder**

`Impact: medium` · `Effort: S` · `Verified: agent-reproduced`

`options.dayFormat` goes straight to `DateFormatter.dateFormat` with no validation, and
`DateFormatter` never signals a bad pattern. `--date-format ''` makes
`string(from:)` return `""`, `relativeDestination` becomes `/Photos/DSCF….RAF`,
`appendingPathComponent` collapses the double slash, and **every file from every shoot
lands in one flat folder** — the entire premise of the tool, silently gone, with `--json`
reporting `"days":[""]`.

A typo is as bad: `--date-format 'zzzz-nope'` yields a day folder literally named
`Central European Summer Time-` for every file. Easy to hit from a script with an unset
shell variable.

```
Sources/fujimm/Options.swift:84
Sources/fujimm/DateResolver.swift:44-51,92
```

**Fix.** Validate at parse time: format two dates 24 hours apart with the pattern, require
the results are non-empty, differ from each other, and contain no `..` component.

---

### `fix-multicard-order`
**Sort the combined item list; make the filename sort locale-independent and total**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

`Scanner` sorts each card's items by day, then kind, then filename, with a comment
promising reproducible runs. `main.swift` then does `scans.flatMap { $0.1.items }`, which
concatenates **card-major** — so with `--all-cards` or repeated `-s`, the progress display
walks days forward, jumps back to the earliest day, and walks forward again. The
aggregated plan tree printed immediately above does not match the copy order.

**Reproduced.** Two sources, one late day and one early day: copy order was `2026-08-05`
then `2026-01-01`, i.e. exactly reversed from the plan.

Two more problems in the same comparator: `localizedStandardCompare` uses the process
locale, so the claimed reproducibility is locale-dependent; and Swift's sort is not
stable, so when a card has wrapped its counter and holds `100_FUJI/DSCF0001.RAF` and
`105_FUJI/DSCF0001.RAF` on the same day, **which one gets the real name and which gets
the `-1` suffix is arbitrary and can flip between runs.**

**Fix.** Sort `allItems` globally after the flatMap; replace `localizedStandardCompare`
with `compare(_:options:.numeric, range:nil, locale:nil)`; add `source.path` as a final
tiebreaker to make the ordering total.

---

### `fix-sibling-naming`
**`siblingKind` re-reads the directory per sidecar and misses `NAME.RAF.xmp`**

`Impact: medium` · `Effort: S` · `Verified: agent-reproduced`

`siblingKind` calls `contentsOfDirectory` once per sidecar and scans the whole listing —
so a directory with S sidecars among N files costs S directory reads and S×N string
operations, each a real round trip on a card reader. On a re-sorted offload folder where
every raw has an XMP, that is quadratic.

The matching rule is also too narrow: it compares `deletingPathExtension`, so
darktable/RawTherapee-style `DSCF6811.RAF.xmp` never matches `DSCF6811.RAF`, falls through
to `.other`, and is then reported as *"not importing unrecognised types: XMP"* — even
though the README lists XMP as a supported sidecar. The comparison is also case-sensitive.

```
Sources/fujimm/Scanner.swift:73,126-138
Sources/fujimm/main.swift:191-196
```

**Fix.** Cache the listing per directory (a one-entry cache keyed on the parent URL is
enough, since the enumerator visits a directory's entries contiguously). Strip repeated
extensions when deriving the base. Exclude known sidecar extensions from the
`unknownExtensions` tally so the warning stops contradicting the documentation.

---

### `fix-silent-date-fallback`
**Report when stills fall off EXIF; stop labelling a fabricated date as `file:mtime`**

`Impact: medium` · `Effort: M` · `Verified: code-read`

`photoDate` returns `nil` whenever `CGImageSourceCreateWithURL` cannot open the file or
the EXIF/TIFF dictionaries are absent — exactly what happens with a RAF from a body whose
RAW codec macOS does not yet ship, or a HIF on an older macOS. `resolve` then silently
uses `filesystemDate`.

On a card straight out of the camera, mtime usually agrees with EXIF. But for the
advertised `fujimm --source ~/old-offload` re-sort, mtime is frequently the *copy* time,
so an entire shoot can be filed under one wrong day with **nothing in the output saying
so**. `ScanResult` has counters for junk, filtered and unreadable items but none for date
fallbacks.

Related: `filesystemDate`'s last resort invents `Date()` and labels it `.fileModified`, so
`--verbose` and `--json` report `file:mtime` for a timestamp that came from nowhere.

```
Sources/fujimm/DateResolver.swift:68,73-97,121-130
Sources/fujimm/Scanner.swift:14-27,91
```

**Fix.** (a) Count items by `DateSource` and print `37 stills had no readable EXIF date —
dated by modification time` in the plan. (b) Add a distinct `DateSource` case for the
fabricated `Date()`. (c) Optionally add a RAF-specific fallback: a RAF is a
`FUJIFILMCCD-RAW` container whose header points at a full embedded JPEG with intact EXIF —
hand that to `CGImageSourceCreateWithData` when ImageIO refuses the RAW itself. Keep (c)
behind a guard that falls back to current behaviour.

---

### `fix-videodate-race`
**`DateResolver.videoDate` races on `result` after its 10 s timeout**

`Impact: medium` · `Effort: S` · `Verified: code-read`

`videoDate` creates an unstructured `Task`, blocks the caller on a `DispatchSemaphore`,
and reads a captured `var result` after `sem.wait(timeout: .now() + 10)`. On the signalled
path the semaphore supplies ordering. **On the timeout path the caller reads `result` on
the scanning thread while the Task is still live and will later write to it** — an
unsynchronised read/write of the same box.

The value the Task eventually produces is silently thrown away, and the caller falls
through to `filesystemDate`, so `--verbose` reports `file:mtime` with no hint that the
requested QuickTime read timed out. The 10 s budget is per file, so N slow clips stall
10N seconds behind a status line set once.

Structurally this also blocks a thread on the cooperative pool — harmless today because
`Scanner.scan` is serial, and exactly the pattern that deadlocks the moment scanning is
parallelised ([`imp-parallel-scan`](#imp-parallel-scan)).

```
Sources/fujimm/DateResolver.swift:101-117
```

This is also the single site that blocks Swift 6 language mode — see
[`tech-swift6`](#tech-swift6).

**Fix.** Narrow version: a lock-protected box plus a distinct `DateSource` for the timeout,
contained to `DateResolver`. Better version: delete the `Task` + semaphore and make the
QuickTime path synchronous behind a dedicated serial queue.

---

### `fix-fuji-signature`
**`hasFujifilmSignature` misses custom folder names, `_DSF` files, and samples an unsorted readdir**

`Impact: medium` · `Effort: S` · `Verified: agent-reproduced`

Three real cards slip through the detector:

- X-series bodies let the photographer name the DCIM folder (CREATE FOLDER), producing
  e.g. `101ANTHO` with no `FUJI` in it.
- Fujifilm writes `_DSF####.JPG` rather than `DSCF####.JPG` whenever the colour space is
  Adobe RGB. The `DSCF`/`.RAF` check does not cover it.
- The filename sniff samples `subdirs.prefix(8)` and `files.prefix(40)` of an **unsorted**
  `contentsOfDirectory`. readdir order on exFAT is hash order, so "the first 8" is an
  arbitrary sample. (`files.prefix(40)` saves no I/O at all — `contentsOfDirectory` has
  already materialised the whole array.)

The user-visible consequence: with two cards inserted and neither recognised, fujimm
refuses with *"Several cards are inserted"* and exit 2 instead of picking the Fujifilm one.

```
Sources/fujimm/Volumes.swift:112-135 (esp. 122,126,129,131)
Sources/fujimm/main.swift:51-64
```

**Fix.** Add `_DSF` to the prefix test; drop the `prefix(40)` truncation; sort subdirs
before truncating; accept a DCIM subfolder matching `/^[0-9]{3}[A-Z0-9_]{5}$/` as a *weak*
DCF signal.

**Risk.** Loosening the DCF heuristic will start flagging Canon/Nikon cards as Fujifilm.
Keep that signal weaker than the FFDB/FUJI/`_DSF` signals rather than folding it into one
boolean.

---

### `fix-readme-claims`
**Correct the README claims that no longer match the code**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

Beyond the collision and re-run promises covered above:

| Claim | Reality |
|---|---|
| Format table | `Formats.swift` also accepts `HEICS` and `MTS2`; the README lists neither. (`MTS2` is not a real extension and should be deleted from the code.) |
| "`fujimm --help` lists everything" | `--other-dir`, `--yes`, `--timezone` and `--destination` are all accepted by `OptionsParser` and absent from `helpText`. |
| Sample output `Destination ~/Documents/Fujifilm` | `main.swift` prints `options.destination.path`, which is always absolute. |
| Sample output shows an ETA | The ETA branch only fires for items over 64 MB, so a typical RAF/JPEG import never displays one. See [`imp-eta-throttle`](#imp-eta-throttle). |
| Dry-run summary | Hardcodes *"would be saved with a `-1` suffix"* even when the real name will be `-4`. **Reproduced.** |
| "Scanner and Copier share nothing but `MediaItem`" | Both take the whole `Options` struct — `Scanner` reads nine fields, `Copier` three. See [`imp-plan-type`](#imp-plan-type). |

---

### `fix-dead-flags`
**Remove or implement `-y/--yes`; stop advertising `--tz` as affecting stills**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

`Options.yes` is declared and set for `-y/--yes` and **read nowhere**. There is no
confirmation prompt for it to skip, and it is absent from `helpText`. An
accepted-and-ignored flag is worse than an unknown one: removing the case would make
`fujimm -y` a clear exit-2 usage error instead of a silent no-op.

Separately, `--help` describes `--tz` as *"Timezone for day grouping"*, but for **stills it
provably cannot change the grouping**: `DateResolver` initialises `exifParser` and
`dayFormatter` with the *same* timezone, so parsing EXIF digits in zone X and formatting
them back in zone X is an identity on the calendar day. The code's own comment says
exactly this. `--tz` only moves videos under the default mtime policy, and shifts the
`--since`/`--until` boundaries.

```
Sources/fujimm/Options.swift:17,82,204
Sources/fujimm/DateResolver.swift:44-57,89-91
```

**Fix.** Either give `-y` the job of gating [`fix-eject-gate`](#fix-eject-gate)'s refusal
(the natural use), or delete it. Reword the `--tz` help to *"affects videos and
`--since`/`--until` only; stills always use the camera's literal EXIF date"*.

---

### `fix-avchd`
**Either scan `PRIVATE/AVCHD` or drop MTS/M2TS from the advertised table**

`Impact: medium` · `Effort: M` · `Verified: reproduced`

`Formats.videoExtensions` lists `MTS`, `M2TS` and `MTS2`, and the README promises them —
but the Scanner can never reach an AVCHD file, for two independent reasons. `Scanner.scan`
roots its enumerator at `card.dcimURL` only, while AVCHD stores clips at
`<volume>/PRIVATE/AVCHD/BDMV/STREAM/*.MTS` — outside DCIM entirely. And even if the scan
root were the volume, `PRIVATE` is in `ignoredDirectories` and gets `skipDescendants()`.

Because the prune happens at the *directory* level, those files never reach the
`unknownExtensions` counter either — so the run reports **nothing at all**. The promise
that unrecognised content is always reported does not apply to pruned directories.

**Reproduced.** A card with `DCIM/100_FUJI/DSCF9999.MTS` and
`PRIVATE/AVCHD/BDMV/STREAM/00000.MTS`: the run found one file. Pointing `--source` at
`PRIVATE` directly does find them — an undocumented workaround.

**Fix.** Pick one. Either walk `PRIVATE/AVCHD/BDMV/STREAM` as a second scan root (and add
`CLIPINF`/`PLAYLIST` `.CPI`/`.MPL` to the ignore path so they do not surface as
unrecognised), or delete `MTS`/`M2TS`/`MTS2` from `videoExtensions` and from the README
table. **Deleting is the cheaper, honest option** and I would take it.

---

### `fix-orphan-parts`
**Sweep stale `.fujimm-*.part` files; let a second Ctrl-C actually kill**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

The `.part`-then-rename design correctly delivers the "never leaves a truncated file
wearing a real name" promise for SIGINT and SIGTERM. Nothing covers SIGHUP (closing the
terminal mid-import), SIGKILL, a crash, or power loss — and **nothing ever sweeps the
leftovers**. The temp name is pid-qualified so the next run picks a different one, and the
leading dot hides the orphan from Finder. A large import killed hard leaves a
multi-gigabyte invisible file in the photo tree permanently.

**Reproduced.** A planted `.fujimm-99999-DSCF0001.JPG.part` survived a clean subsequent
run untouched.

Compounding it: `installSignalHandlers` replaces SIGINT's disposition with a handler that
only sets a flag and never restores the default, so a user who presses Ctrl-C during a
stalled `read()` **cannot escalate** — a second Ctrl-C does nothing and they must reach for
`kill -9`, which is exactly the case that strands a `.part`. The cancel flag is also only
tested once per 4 MB chunk.

That `.gitignore` already lists `*.part` suggests stray part files have been seen in
practice.

**Fix.** On startup, glob the destination for `.fujimm-*.part` and report or remove them
(restrict removal to files whose embedded pid is not a live process, or gate it behind
`--clean`, to avoid racing a concurrent fujimm). Handle SIGHUP like SIGINT. On the second
signal, restore `SIG_DFL` and re-raise.

---

### `fix-install-sh`
**The `~/.local/bin` fallback never fires, and there is no toolchain preflight**

`Impact: medium` · `Effort: S` · `Verified: agent-reproduced`

The comment says *"Prefer a directory we can write to without sudo"*, but the `elif` is
`[ -d "$HOME/.local/bin" ]` — which fires only if the directory **already exists**. A user
on a clean Mac with no `~/.local/bin` and a root-owned `/usr/local/bin` falls through to
`DEST=/usr/local/bin` and gets a sudo prompt: exactly the outcome the comment claims to
avoid.

Worth understanding before anyone "simplifies" the next line: `||` and `&&` have equal
precedence and are left-associative in POSIX sh, so
`[ -w "$DEST" ] || mkdir -p "$DEST" && [ -w "$DEST" ]` parses as
`([ -w $DEST ] || mkdir -p $DEST) && [ -w $DEST ]`. **It is accidentally correct**, and the
trailing re-test is load-bearing — `mkdir -p` on an existing non-writable directory exits
0, so dropping it would send a root-owned `/usr/local/bin` down the non-sudo path.

Also: the `2>/dev/null` on the `[` tests is cargo cult (`test` writes nothing to stderr for
a missing path), and there is no preflight at all — no `command -v swift`, no
`xcode-select -p`, no `sw_vers`. A macOS 12 user gets a raw SwiftPM platform error instead
of *"fujimm needs macOS 13 or later"*.

**Fix.** Make the fallback unconditional and let `mkdir -p` create it; rewrite the
condition as an explicit if/else; drop the redirects; add the three preflight checks.

**Risk.** Changing the default from `/usr/local/bin` to `~/.local/bin` changes where an
existing user's next install lands, potentially leaving a stale binary earlier on PATH.
Warn if a different `fujimm` is already on PATH.

---

## Improvements

Things that already work, done better.

---

### `imp-parallel-scan`
**Read EXIF concurrently; show scan progress**

`Impact: medium` · `Effort: M` · `Verified: code-read`

`Scanner` walks the tree on one thread and calls `DateResolver.resolve` inline, which
opens each photo with `CGImageSourceCreateWithURL`. On a card with thousands of RAF files
this dominates the pre-copy wait — during which the only feedback is a **static
`Scanning …` line with no counter**, set once and never updated.

```
Sources/fujimm/Scanner.swift:47-113,91
Sources/fujimm/DateResolver.swift:44-57   shared DateFormatter instances
Sources/fujimm/main.swift:124-127         the static status line
```

**Fix.** Two stages. First make the status line report `Scanning… 1,240 files` so the wait
is legible — that is an hour's work and most of the perceived benefit. Then parallelise:
collect the file list first, then resolve dates with a bounded `TaskGroup` or
`concurrentPerform`.

**Prerequisite.** `DateFormatter` is **not thread-safe** and `DateResolver` shares two
instances across all calls. Naive parallelisation produces wrong dates, not crashes, which
is the worst failure mode for this tool. Give each worker its own formatter (or move to
`Date.ISO8601FormatStyle`/`Calendar` arithmetic), and land
[`fix-videodate-race`](#fix-videodate-race) first — its semaphore-on-a-Task pattern
deadlocks the moment the caller is in a structured-concurrency context.

---

### `imp-copy-overlap`
**Overlap reading from the card with writing to disk**

`Impact: medium` · `Effort: M` · `Verified: code-read`

`streamCopy` reads 4 MB then writes 4 MB in the same loop iteration, so the SD reader is
idle during every write and the SSD is idle during every read. On a UHS-II reader feeding
an NVMe SSD — where the reader is the bottleneck by a wide margin — that is real
throughput left on the table. The 4 MB buffer is also allocated fresh per file.

```
Sources/fujimm/Copier.swift:26,182,184-213
```

**Fix, in increasing order of risk:** hoist the buffer to an instance property; then
double-buffer with a producer/consumer pair; then consider whole-file concurrency (N files
in flight). Note that `fcopyfile` is not obviously a win here since the progress callback
and the inline SHA-256 both need the bytes to pass through. APFS `clonefile` is
unavailable — source and destination are different devices by definition.

Also worth measuring: `F_NOCACHE` and `F_RDAHEAD` are set on the input fd but not the
output, and there is an `fsync` per file. Given the `.part`-then-rename design, per-file
`fsync` durability is arguably not required and costs real time across thousands of files.

**Risk.** This is the one code path that touches user data. Do not start it before
[`fix-test-net`](#fix-test-net) and [`tech-run-type`](#tech-run-type).

---

### `imp-verify-double-hash`
**`--verify` re-reads far more than it needs to**

`Impact: medium` · `Effort: S` · `Verified: code-read`

Two separate wastes:

1. `isAlreadyImported` under `--verify` hashes the source **and** the destination for
   every already-present file. Re-verifying a completed 20.7 GB import reads about 41 GB —
   more I/O than the original import's read side.
2. When the hashes differ, the copy proceeds and `streamCopy` hashes the source a *second*
   time during the read.

`sha256(of:)` also uses `FileHandle` without `F_NOCACHE`, so it pollutes exactly the page
cache `streamCopy` deliberately avoids.

```
Sources/fujimm/Copier.swift:180,207-209,227-232,258-266
```

**Fix.** Reuse the in-stream digest. Set `F_NOCACHE` in `sha256(of:)`. Longer term, this is
what [`feat-manifest-audit`](#feat-manifest-audit) solves properly: re-verify against
recorded digests instead of re-reading the card.

Same item: **size the free-space check to the work actually remaining.** Today it compares
the sum of *every scanned item* against available capacity before any skip decision is
made, so re-running a 20 GB import on a disk with 5 GB free exits 2 with "not enough
space" despite intending to copy nothing. And the check is skipped entirely under
`--dry-run` — so the one preflight most likely to abort the real run is the one "look
before you leap" does not perform. (The probe also falls back only one directory level, so
a `--dest` two levels below any existing directory skips the check silently.)

---

### `imp-redundant-stat`
**Stop stat-ing every file twice**

`Impact: low` · `Effort: S` · `Verified: code-read`

The enumerator is created with `.fileSizeKey` and `.isRegularFileKey`, then `Scanner` calls
`attributesOfItem` separately for size and mtime. Reading both from the enumerator's
prefetched `resourceValues` halves the stat calls across a multi-thousand-file card.
`DateResolver.resolve` currently takes a `[FileAttributeKey: Any]` dictionary and would
need its signature changed. Folds naturally into [`fix-symlink-size`](#fix-symlink-size),
which is about the same unread keys.

---

### `imp-progress-tty`
**Progress is gated on stdout but written to stderr**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

`Term.isTTY` tests `isatty(fileno(stdout))`, but `Term.status` and `Term.clearStatus` write
to `FileHandle.standardError`. `Term.columns` has the same mismatch.

**Reproduced.** `fujimm … | cat` with stderr on a terminal wrote **zero bytes** of progress
— the whole progress display is silently disabled by piping stdout, even though stderr is
still a terminal and would render it correctly. This is the common case for anyone logging
a run.

**Fix.** Gate status output on `isatty(fileno(stderr))` and read `columns` from stderr too.
While there: `Term.status` truncates with `String.count`, which is grapheme count, so a
filename with wide CJK characters or emoji overflows the line. Use a width-aware measure.

Related: there is no `--color=always|never|auto`. `NO_COLOR` is honoured, which covers most
of it, but a `--color` flag is a one-liner and CI logs want it.

---

### `imp-eta-throttle`
**Show an ETA for every file size**

`Impact: low` · `Effort: S` · `Verified: code-read`

The in-copy progress callback only refreshes the status line when `item.size > 64 MB`, so
importing 200 compressed RAF files of ~25–50 MB shows a per-file line with a rate but
**never the ETA the README advertises** in its sample output.

```
Sources/fujimm/main.swift:247-257
```

**Fix.** Replace the size gate with a time-based throttle — refresh at most every 100 ms.
That gives a smooth ETA at every file size and costs less than the current branch on large
files.

---

### `imp-exit-code-semantics`
**Exit 1 for "nothing to import" makes a clean re-run look like a failure**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

`main.swift` exits 1 when `allItems` is empty, sharing the code with "no card found". A
launchd job or shell pipeline written as `fujimm --json && post-process` treats a
**fully-imported card as an error**. These are different situations: one is "I could not
find your card", the other is "everything is already safe".

**Reproduced.** An empty card yields `Nothing to import.` and exit 1.

**Fix.** Give "nothing new to import" exit 0, keep exit 1 for "no card found", and add
`--fail-on-empty` for anyone who wants the old behaviour. Document it in the README exit
table and the CHANGELOG — it is a breaking change for anyone already scripting against it,
which is precisely why it should happen before the userbase grows.

---

### `imp-json-contract`
**Version the JSON, unify its two shapes, add per-file detail**

`Impact: medium` · `Effort: M` · `Verified: reproduced`

`--json` is hand-built by string interpolation in two places with two different shapes,
with no version field.

**Reproduced.** `fujimm --list --json` with no card emits
`{"status":"no-card","cards":[],"imported":0}`, while `--list --json` *with* a card emits
`{"cards":[…]}` — different keys for the same command. The summary object is a third
shape.

`jsonString` does escape correctly, so this is a contract problem rather than a
correctness one. But there is no per-file detail at all: `--verbose --json` gives a
scripter nothing beyond aggregates.

**Fix.** Add `"schemaVersion": 1`; make `--list` emit one consistent shape; move to
`Codable` + `JSONEncoder` so the structure is declared once; add the arrays
[`fix-scan-failures-invisible`](#fix-scan-failures-invisible) needs. A per-file array is
the natural home for [`feat-manifest-audit`](#feat-manifest-audit)'s data.

---

### `imp-interrupt-resume`
**Ctrl-C on a 10 GB clip throws away everything already copied**

`Impact: medium` · `Effort: M` · `Verified: code-read`

On cancellation `streamCopy` returns `.cancelled` and `Copier.copy` removes the temp file.
Re-running re-copies that file from byte zero. The summary's "Re-run to resume" is
per-*file*, not per-byte: a 4 GB ProRes clip interrupted at 99% restarts from nothing. The
temp name embeds the pid, so a resumed run could not find the old part even if it tried.

**Fix.** Keep the `.part` on cancellation, name it deterministically (drop the pid, or
record it), and resume by offset — validating the existing prefix under `--verify` before
appending.

**Risk.** Resuming a partial file is exactly the class of feature that corrupts data if the
prefix is not validated. Do not ship it without [`fix-test-net`](#fix-test-net) covering
the truncate-and-resume case, and consider making resume opt-in at first.

---

### `imp-plan-type`
**Extract a `Plan` type; `main.swift` recomputes what `ScanResult` already exposes**

`Impact: medium` · `Effort: M` · `Verified: code-read`

`ScanResult` declares `totalBytes`, `days`, `photoCount`, `videoCount` and `otherCount` —
and `main.swift` uses **none of them**, recomputing `totalBytes` inline and building its
own per-day dictionary by hand. Meanwhile `skippedByFilter` is incremented in four places
and read in zero.

**Fix.** A `Plan` built by a planner from `[(Card, ScanResult)]`, plus an `ImportSummary`
that owns the tally loop. Then the plan printer, the JSON emitter and the human summary all
become functions of a value you can construct in a test, instead of statements that exist
only while the process runs.

While in there, splitting `Options` into a `LayoutPolicy` (`dayFormat`, dir names, `flat`)
and a `CopyPolicy` (`dryRun`, `overwrite`, `verify`) would let a `Scanner` test construct
its input without fabricating a full `Options` — and would make the README's "share
nothing but `MediaItem`" sentence true.

**Risk.** Refactoring an area with no coverage. Sequence after
[`fix-test-net`](#fix-test-net). If you only do half, do the `Plan` type and leave
`Options` alone — the `Options` split touches every call site and is the part most likely
to be net churn.

---

### `imp-trademark-line`
**Add a not-affiliated-with-Fujifilm line**

`Impact: low` · `Effort: S` · `Verified: code-read`

Licensing is clean — MIT is present and there is genuinely no third-party code to
attribute. The exposure is the name. `fujimm` is a truncation of a registered trademark,
and the README uses FUJIFILM's marks heavily (Fujifilm, X-T5, X-H2, GFX100 II, FinePix,
instax, X-App). Describing what hardware a tool works with is nominative fair use, but a
product name derived from the mark plus unqualified use throughout the docs is the pattern
that draws a rename request.

One line at the bottom of the README costs nothing:

> Not affiliated with, endorsed by, or sponsored by FUJIFILM Corporation. Fujifilm, X-T5,
> GFX, FinePix and instax are trademarks of FUJIFILM Corporation.

Avoid Fujifilm's logo, wordmark styling or brand colours in any future README assets.

---

## Technologies

Platform, tooling, architecture, distribution.

---

### `fix-test-net`
**A fixture-card integration test that mechanically enforces the read-only promise**

`Impact: critical` · `Effort: M` · `Verified: agent-reproduced` · *(filed under fixes because it ships first)*

The README's central claim is *"The card is read-only, structurally"* and **nothing
verifies it.**

A full integration test needs no camera, no SD card and no committed binary fixtures. A
fixture card is `mkdir -p card/DCIM/100_FUJI`, a few files from `/dev/urandom`,
`touch -t 202606150912` to fabricate distinct mtime days, plus `._DSCF*` and `.DS_Store`
stubs and empty `FFDB/` and `MISC/` directories to exercise `Formats.isJunk` and
`ignoredDirectories`. For the EXIF path, a ~793-byte JPEG carrying a `DateTimeOriginal`
can be synthesized at test time with `CGImageDestinationAddImage` — so `photoDate` is
testable with **zero checked-in binaries**.

The highest-value assertions, in order:

1. **Hash the card tree before and after a real run and assert byte-identity.** This turns
   the README's headline promise into a test, and it is the one assertion that would have
   caught [`fix-path-escape`](#fix-path-escape).
2. Parse the `--json` line and assert `scanned`/`copied`/`days`.
3. Run twice; assert the second run reports `copied:0, skipped:N`.
4. Assert `--dry-run` planned counts equal the subsequent real run's copied counts — the
   dry-run contract nothing currently checks.
5. Plant a same-named, **same-sized**, different-content file and assert a second file
   appears. *(Fails on `main` today — that is [`fix-silent-drop`](#fix-silent-drop).)*
6. Run three times against a genuine collision and assert no growth. *(Fails on `main`
   today — [`fix-rerun-duplicates`](#fix-rerun-duplicates).)*

**Risk.** Until [`tech-run-type`](#tech-run-type) lands, this test spawns the built binary
as a subprocess, which depends on build layout (`swift build --show-bin-path`) and is
slower than in-process. That is an acceptable trade — a subprocess test that exists beats
an in-process test that does not — and the same assertions survive the refactor unchanged.

---

### `tech-run-type`
**Move `main.swift`'s top-level orchestration into a `Run` type**

`Impact: high` · `Effort: M` · `Verified: agent-reproduced`

**A library-target split is not required, contrary to the obvious assumption.** SwiftPM
attaches a `.testTarget` to an `executableTarget` and `@testable import fujimm` reaches
`Formats`, `Fmt`, `OptionsParser`, `DateResolver`, `Scanner`, `Copier` and `Volumes`
today. Top-level *functions* (`jsonString`, `describe`) are reachable and callable too.

What is genuinely untestable is `main.swift`'s 35 top-level statements. Top-level `let`/`var`
are initialised as a side effect of running `main`, which never happens in a test host —
touching one from a test crashes the process with SIGSEGV rather than failing an assertion.
So the entire import policy — multi-card disambiguation, the import-into-itself guard, the
free-space check, the copy loop and its byte accounting, the summary tally, and every exit
code — is reachable only by spawning the binary.

**The minimal restructure is not a target split.** Move the top-level code into
`Sources/fujimm/Run.swift` as
`enum Run { static func main(_ argv: [String]) -> Int32 }`, reduce `main.swift` to one
line, and turn every `exit(n)` into `return n`. That costs zero access-modifier churn —
there is not a single `public` in the package today — and makes exit codes assertable.

Defer a `fujimmCore` library target until there is a second consumer; splitting now would
force `public` onto roughly the entire surface for no gain.

**Risk.** It touches the one file with no coverage. Do it as a pure mechanical move in a
single commit with no behaviour change, pinned by [`fix-test-net`](#fix-test-net) first.
Threading an output abstraction through ~60 print sites is the tedious part; an acceptable
first cut keeps printing directly and only returns the exit code.

---

### `tech-swift6`
**Swift 6 language mode is one 10-line fix, not a migration**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

**Reproduced.** Building the unmodified tree with `-swift-version 6` produces **exactly one
error**:

```
Sources/fujimm/DateResolver.swift:105:9: error: sending value of non-Sendable type
'() async -> ()' risks causing data races [#SendingRisksDataRace]
```

Everything else is clean. Specifically:

- `nonisolated(unsafe) var gInterrupted` in `Copier.swift` is already the correct idiomatic
  escape hatch for a signal handler and draws no diagnostic.
- The C-function-pointer closures in `installSignalHandlers` are non-capturing and fine.
- Every file-scope `var` in `main.swift` is silently fine, because top-level variables in
  `main.swift` are implicitly `@MainActor`-isolated.

So the whole Swift 6 story is [`fix-videodate-race`](#fix-videodate-race).

**Sequencing.** Bumping `swift-tools-version` to 6.0 raises the minimum toolchain from
Swift 5.9 (Xcode 15) to Swift 6.0 (Xcode 16), contradicting the README's "Swift 5.9+".
Lower-risk path: keep tools-version 5.9, fix `DateResolver.swift:105`, add
`-strict-concurrency=complete` as warnings-only, and adopt language mode v6 only when
you are ready to drop Xcode 15 and update the README.

---

### `tech-ci`
**A two-job macOS GitHub Actions workflow; free on a public repo**

`Impact: high` · `Effort: S` · `Verified: reproduced`

There is no `.github` directory, so nothing verifies the committed state even builds on a
machine other than the author's.

**Reproduced.** A clean debug build takes 4.15 s; a release build about 4.7 s. The whole CI
budget is dominated by checkout and runner spin-up — a job lands around 1–2 minutes.

Minimum useful `ci.yml`, on push and pull_request, `runs-on: macos-15`:

- **Job 1:** `swift build -c release` and `swift test`.
- **Job 2:** `swift-format lint --recursive --strict Sources/` — `swift-format` ships in the
  Xcode toolchain, so no install step and no external dependency, consistent with the
  zero-dependency stance. You would also add a `.swift-format` config; none exists, and
  neither `swift-format`, `swiftformat` nor `swiftlint` is currently installed here.

Add a matrix over `macos-14`/`macos-15` only once you care about the older SDK.

Separately, a `release.yml` on `v*` tags should build a **universal** binary with
`swift build -c release --arch arm64 --arch x86_64`, tar it, and attach it to the release —
plain `swift build -c release` produces an arch-native binary only, which matters the moment
anything prebuilt is distributed.

**Risk.** A lint job on a never-formatted codebase produces a large first diff. Run
`swift-format` once as its own commit before turning the job `--strict`, or start it
non-blocking.

---

### `tech-homebrew`
**A tap with a build-from-source formula is the right first distribution channel**

`Impact: high` · `Effort: M` · `Verified: agent-reproduced`

Today the only install route is `git clone && ./install.sh`. For a macOS CLI, users expect
`brew install`. Evaluating what a solo maintainer can sustain:

| Option | Verdict |
|---|---|
| **(a) Tap, source formula** | **Do this.** A `homebrew-fujimm` repo with `Formula/fujimm.rb`: url/sha256, `depends_on xcode: ["15.0", :build]`, `system "swift", "build", "-c", "release", "--disable-sandbox"`. No Apple Developer account, no signing, no notarization — the binary is built locally and never crosses a quarantine boundary. `v1.0.0` is already tagged, so the tarball URL exists today. |
| (b) Tap with bottles | ~3× the maintenance (`brew test-bot` per macOS version, bottle hosting) for a build that takes 5 seconds. Negative payoff. |
| (c) Signed + notarized `.pkg` | $99/yr Developer ID, `productbuild`, `notarytool submit --wait`, stapling, cert secrets in CI. Right for a GUI app, overkill here. |
| (d) mise/asdf | No meaningful ecosystem for Swift CLIs. Skip. |

Option (a) composes with [`tech-ci`](#tech-ci): tag, CI builds and attaches the tarball, you
bump url and sha256. Keep `install.sh` for contributors; make `brew install` the primary
README instruction.

**Risk.** A tap is a second repo to keep in sync, and a stale sha256 after a re-tag produces
a confusing failure. Automate the bump from the release workflow. Also test the
`depends_on xcode: :build` path — users with only Command Line Tools and no full Xcode may
hit a formula-level rejection even though `swift build` would work for them.

---

### `tech-release-process`
**CHANGELOG, GitHub Release, and a version-tag assertion**

`Impact: medium` · `Effort: M` · `Verified: reproduced`

Today the only way a user learns a new version exists is to notice the repo and `git pull`.
No update check, no published artefact, no checksum, no CHANGELOG. With one commit in
history there is no record of what 1.0.0 even contains.

Minimum credible process:

- **CHANGELOG.md.** This is the release notes, and it is the only channel through which a
  user learns that, say, [`fix-silent-drop`](#fix-silent-drop) was fixed and they should
  re-import.
- **A tag-vs-version assertion** — see [`tech-version-tag`](#tech-version-tag).
- **`gh release create`** with notes and a SHA-256 of a universal binary.
- **The Homebrew tap** — [`tech-homebrew`](#tech-homebrew).

**Skip** CONTRIBUTING.md and SECURITY.md. For a zero-dependency, no-network tool with one
maintainer they are cargo cult; a *"PRs welcome, run ./install.sh"* line does the same work.
A man page is likewise unnecessary while `--help` exists — but a CI check that greps
`helpText` against the README flag list would have caught the drift in
[`fix-readme-claims`](#fix-readme-claims).

**Also:** add `.claude/settings.local.json` to `.gitignore`. It is currently neither tracked
nor ignored, and full of local absolute paths waiting for a `git add -A`.

---

### `tech-version-tag`
**Bind `Options.version` to the git tag with a CI assertion**

`Impact: medium` · `Effort: S` · `Verified: reproduced`

`Options.version` is the literal `"1.0.0"`. The repo has a `v1.0.0` tag, so today they
agree — but nothing enforces it, and there is one commit of history on which to build a
habit. The failure mode is the standard one: tag `v1.1.0`, forget the literal, and every
user's `fujimm --version` reports 1.0.0 forever. That matters more than usual here because
both a Homebrew formula and a `--json` consumer key off it.

**Do the cheap thing, not the clever thing.** A SwiftPM prebuild plugin stamping a generated
`Version.swift` from `git describe` works, but drags plugin sandboxing and a
non-reproducible source tree into a package whose selling point is that `swift build` works
offline with zero moving parts. Instead: keep the literal as the single source of truth, and
add a release-workflow job that fails if `${GITHUB_REF_NAME#v}` does not equal the string
grepped out of `Options.swift`. Five lines of YAML, zero build-time cost, mistake
impossible to ship.

---

### `tech-dead-frameworks`
**Remove the unused `CoreServices` and `DiskArbitration` links**

`Impact: low` · `Effort: S` · `Verified: reproduced`

**Reproduced.** `Package.swift` links four frameworks; the only imports across all eight
files are `Foundation`, `CryptoKit`, `ImageIO` and `AVFoundation`. Grepping for
`CoreServices`, `DiskArbitration`, `DADisk`, `MDItem`, `LSCopy` across `Sources/` returns
zero hits. Card detection uses `FileManager.mountedVolumeURLs`, not `DADiskRef`, and
`Volumes.eject` shells out to `diskutil`.

Not purely cosmetic: both appear as hard load commands in the shipped binary, so dyld maps
**CoreServices** — a very large umbrella framework — on every invocation of a tool whose
whole job is to finish in a few seconds.

The `Package.swift` header comment is itself inconsistent, listing DiskArbitration but
omitting CoreServices, which suggests both were added speculatively.

**Fix.** Delete both `.linkedFramework` lines and fix the comment. (`ImageIO` and
`AVFoundation` are technically redundant too, since the `import` statements drive
autolinking, but leaving them is harmless documentation. The two dead ones are not.)

---

### `tech-no-linux-port`
**Do not port to Linux**

`Impact: low` · `Effort: XL` · `Verified: code-read` · *see also [Won't do](#wont-do)*

A card reader on a NAS is a reasonable wish and this is the wrong codebase to grant it in.
Four load-bearing behaviours are Darwin-only with no drop-in substitute:

- `photoDate` is pure ImageIO. Reading EXIF `DateTimeOriginal` out of a RAF on Linux means
  an external dependency (libexif, exiv2) or a hand-rolled TIFF/IFD parser — the single
  most valuable thing the tool does, and the last thing to reimplement untested.
- `videoDate` is AVFoundation, with no Linux analogue.
- SHA-256 is CryptoKit; the replacement is swift-crypto, an external dependency that breaks
  the offline-zero-dependency promise in both `Package.swift` and the README.
- `Volumes.detectCards` is built on `mountedVolumeURLs` + `volumeIsRemovable`, which
  swift-corelibs-foundation does not usefully implement. On Linux you would parse
  `/proc/mounts` or talk to udisks2.

Smaller cuts: `F_NOCACHE`/`F_RDAHEAD` are Darwin `fcntl` commands (Linux spells it
`posix_fadvise`), and `volumeAvailableCapacityForImportantUsageKey` is Darwin-only. (`ioctl
TIOCGWINSZ` in `Term.swift` does port.)

A Linux port is a second product sharing a name. If you want the option open, the cheap
insurance is to define a date-resolution protocol and a `CardLocator` protocol — which the
testability work wants anyway — so the platform-specific code sits behind two seams. Do
that as a **side effect** of testability, never as speculative generality.

---

## Product features

New user-facing capability. Ranked.

---

### `feat-stacks`
**Make the frame, not the file, the unit of import — and add `--only raw|jpeg`**

`Impact: critical` · `Effort: M` · `Verified: agent-reproduced` · **Build this first**

`Formats.kind` maps RAF and JPG to the same `.photo` bucket, so `--only` can select
photos-vs-videos but has **no way to say "RAW only" or "JPEG only"** — the single most
common request from a Fujifilm shooter, because Fuji bodies shoot RAW+JPEG constantly and
the JPEG is the film-sim deliverable while the RAF is the negative.

The same missing primitive is the root cause of [`fix-sidecar-day`](#fix-sidecar-day):
`siblingKind` makes a sidecar inherit only the *bucket* of its sibling, never its *date*.

**The fix and the feature are the same primitive.** Group items by `(directory, basename)`,
elect a primary (RAF > HIF > JPG > MOV), resolve the date **once** for the primary, and give
every member of the stack that date and that day folder. Once stacks exist, `--only raw`,
`--only jpeg`, `--raw-dir Raw --jpg-dir Jpeg` and `--jpeg-with-raw` all fall out of one
`MediaStack` type in `Scanner`.

Entirely on-brand: it still copies the same files into day folders. It just stops splitting
a frame's parts across two days.

> An auditor ran this against the real offload tree at `~/Documents/Fujifilm`: all 47 `.xmp`
> files collapsed onto `2026-08-06` (the evening Camera Raw was run) while their RAFs sat in
> `2026-08-05`, rendering the plan as `2026-08-05 Photos/ 38` and `2026-08-06 Photos/ 56`
> (9 RAF + 47 orphaned sidecars).

**Risk.** Electing a primary is ambiguous for a JPG+MOV stack (Fuji's "movie for still"
modes) or when two extensions in one stack have genuinely different capture times. Sidecars
whose sibling was filtered out by `--only` or `--since` need a defined fate — pick "drop,
and report the count", and say so in `--help`. `--flat` plus `--only raw` needs an explicit
meaning.

---

### `feat-manifest-audit`
**Write a manifest with SHA-256s; add `fujimm --audit <dest>`**

`Impact: high` · `Effort: L` · `Verified: agent-reproduced`

`Copier` already computes the source SHA-256 under `--verify`, compares it once, and
**throws it away** — `CopyRecord` has no digest field and the `--json` summary is
aggregate-only. No per-file record, no source path, no checksum, no date source, no camera.

That is the whole difference between a copy tool and a tool you trust.

- `--manifest` (implied by `--verify`) writes `<dest>/.fujimm/<timestamp>.json` containing,
  per file: source volume name and path, destination relative path, bytes, mtime, sha256,
  `DateSource`, camera model.
- `fujimm --audit <dest>` re-hashes what is on disk against the newest manifest and reports
  missing / changed / extra.
- `fujimm --audit <dest> --against /Volumes/Untitled` answers the only question that matters
  before you reuse a card: *"is every frame on this card present, byte-identical, at that
  destination?"*

Hedge sells this as MHL manifests; it is the reason people pay for it. It is on-brand
because a JSON file next to the photos is **not a catalogue** — delete it and nothing
breaks. It is also the prerequisite for [`feat-only-new`](#feat-only-new) and the only
honest substitute for a card-format feature (see [Won't do](#wont-do)).

**Risk.** Keep it a flag, not a subcommand — the pitch is one command. Re-hashing a 200 GB
archive is minutes of I/O, so it needs progress and a `--sample N` mode. **The manifest must
never be authoritative over the bytes:** if they disagree, the file wins and the tool says
so.

---

### `feat-multi-dest`
**Accept `--dest` more than once: read the card once, write N copies, verify each**

`Impact: high` · `Effort: M` · `Verified: code-read`

`Options.destination` is a single URL and a repeated `--dest` silently overwrites the
previous value. Every working photographer offloads to two places — a fast working SSD and
an archive — and today that means running fujimm twice, reading every byte off the card
twice. **The card is the bottleneck.**

Change `destination: URL` to `destinations: [URL]`; in `streamCopy`, open N output
descriptors and write each 4 MB buffer to all of them, hashing the buffer once. The verify
story gets *better*: one source hash, N destination hashes, and the manifest records which
destinations hold a verified copy. Safety invariants are untouched — the card is still
`O_RDONLY`, each destination still gets its own `.part` and rename.

**Risk.** Partial-failure semantics get harder. Decide up front: a file counts as copied
only when **every** destination has it, and the exit code is 3 with a per-destination
breakdown. A slow destination (spinning archive, network volume) throttles the whole loop —
document it, and consider `--dest-async` to queue the second. The ETA maths needs to divide
by N.

---

### `feat-film-sim`
**Surface the film simulation, body and lens macOS already decodes**

`Impact: high` · `Effort: S` · `Verified: agent-reproduced`

This is the thing a tool with "fuji" in the name should do that Lightroom Classic will not
do for you — and it costs almost nothing, because ImageIO already parses the Fujifilm
MakerNote and `DateResolver` **already has the parsed dictionary in hand and drops it**.

`photoDate` calls `CGImageSourceCopyPropertiesAtIndex` and reads exactly three keys. On a
real X-T5 RAF that same dictionary also contains:

```
{PictureStyle}  FilmSimulation = ("F0/Standard", 0, 0);  Monochrome = (0,0,0); …
{ExifAux}       LensModel = "AF 23/1.4 XF";  SerialNumber = 4D011128;  LensInfo = (23,23,1.4,1.4)
{TIFF}          Make = FUJIFILM;  Model = X-T5
```

Add `camera`, `lens`, `filmSim`, `bodySerial` to `MediaItem`, then: `--film-sim acros` /
`--film-sim classic-neg` as a scan filter alongside `--only`/`--since`; the sim, body and
lens in `--verbose`, the manifest and `--json`; and a one-line breakdown in the summary —
`Classic Neg 82 · Acros 31 · Provia 26`.

**Explicitly do NOT add a film-sim folder axis.** The folder name must stay a date.

Neither Lightroom Classic nor Capture One exposes film simulation as a filterable field for
RAF, so *"pull just tonight's Acros frames off the card"* is genuinely something only this
tool can do.

**Risk.** Exactly one value (`"F0/Standard"`) was verified on one body. The mapping from
ImageIO's F-codes to marketing names (Velvia, Astia, Classic Chrome, Acros, Classic Neg,
Nostalgic Neg, Reala ACE, Eterna) is **unverified** and needs a card shot with varied sims
before shipping the table — Acros/monochrome probably comes from the separate `Monochrome`
key, not `FilmSimulation`. Newer sims on newer firmware may return an unmapped code, so the
filter must accept the raw code and print unknown codes verbatim rather than swallowing
them. Note `kCGImagePropertyMakerFujiDictionary` returns nil and `kCGImagePropertyExifMakerNote`
is absent, so `{PictureStyle}` is the only route — but it is system-provided, no dependency,
no hand-rolled IFD parser.

---

### `feat-last-day`
**`--last-day` / `--days N` / `--newest N`**

`Impact: medium` · `Effort: S` · `Verified: code-read`

The only time filters take literal dates. The overwhelmingly common intent after a shoot is
*"just get tonight's frames off, I'll deal with the rest later"*, which today means looking
up the date and typing `--since 2026-08-07`.

- `--last-day` — the newest day **present on the card**, whatever that is. That is the right
  semantic, because you may be importing the following morning.
- `--days N` — the N newest distinct days.
- `--newest N` — the N most recent files, for the "just the last burst" case.

All three are pure post-scan filters over already-sorted items: no new metadata reads, no
change to `Copier`. `--last-day` in particular makes
`fujimm --last-day --verify --eject` a muscle-memory one-liner.

**Risk.** "Newest day on the card" is ambiguous if the camera clock was wrong or two bodies
wrote to one card — print the day it selected before copying. `--newest N` interacts badly
with [`feat-stacks`](#feat-stacks): it must count **stacks, not files**, or it will import a
RAF without its JPEG.

---

### `feat-foreign-raw`
**Add ARW/CR2/CR3/NEF/ORF/RW2/GPR — broaden the format list, not the brand**

`Impact: medium` · `Effort: S` · `Verified: code-read`

The tool already works on any DCIM tree and already accepts HEIC, DNG, MP4 and MTS, so a
photographer with an a7 or a GoPro in the bag will absolutely try it. Today those cards
import the JPEGs and dump every raw file into "unrecognised file types" — a loud, alarming
and easily avoided first impression. (`ARW ×340` is the message an a7 user gets.)

Adding ARW, CR2, CR3, CRW, NEF, NRW, ORF, RW2, PEF, SRW, X3F, GoPro GPR, plus SRT (DJI
flight-log subtitles) and WAV (voice memos) as sidecars, is roughly eight lines and requires
**no new logic** — ImageIO reads EXIF `DateTimeOriginal` from all of them.

This is the on-brand version of "beyond Fujifilm": the tool stays Fuji-first in its
detection heuristics, its ignored directories (`FFDB`/`UPD`) and its film-sim reporting, and
simply stops being rude about the other card in your bag.

**Risk.** Dilution. The moment ARW is in the table, someone files an issue asking for Sony's
split AVCHD structure or Canon's CR3 movie sidecars, and the answer has to be a firm no.
Draw the line in the README: *fujimm recognises other manufacturers' files so it does not
lose them, and does nothing brand-specific for them.*

---

### `feat-session-grouping`
**`--session <hours>`: keep a shoot that crosses midnight in one folder**

`Impact: medium` · `Effort: M` · `Verified: code-read`

Grouping is purely calendar-day. A wedding reception, a concert, a night-sky session or a
New Year's job running 22:00–02:30 is split across two folders, and the second contains four
frames.

`--session 6h`: sort by instant, start a new session whenever the gap exceeds the threshold,
name the folder from the **first** frame of the session using the existing `--date-format`.
Implement as a post-pass over `result.items` after the sort, rewriting
`relativeDestination` — so `Copier` and everything downstream is untouched.

**Risk.** It breaks the invariant the README leans on hardest: that the folder name equals
the literal EXIF day. A frame shot at 01:40 filed under the previous date will look like a
bug to someone who did not pass the flag, so it must be **opt-in forever**, and `--verbose`
must print the session boundaries it chose. It also needs a reliable `instant` for videos —
fine under the default mtime policy, offset by an hour under `--video-date quicktime` on
Fuji files.

---

### `feat-shoot-log`
**Make the plan and summary something you would paste into a shoot log**

`Impact: medium` · `Effort: M` · `Verified: agent-reproduced`

`2026-08-05  3.5 GB  Photos/ 38` does not tell you whether that is the morning walk or the
evening session, which body it came from, or what glass was on. Every instant is already
sitting in `ResolvedDate.instant`, and with [`feat-film-sim`](#feat-film-sim) the camera and
lens are there too.

Extend each day line to:

```
2026-08-05  19:33–20:32  3.5 GB  38 photos · 3 clips  X-T5 · XF23mmF1.4 · ISO 125–3200
```

and add `--summary md` writing a Markdown block per import (day, time range, counts, gear,
film sims, first and last frame). This is a **report, not a catalogue** — the receipt you
paste into Notion or a job sheet. Composes with the manifest: same data, two renderings.

> The real tree's per-day EXIF ranges are 06:05–06:31, 17:37–19:42, 19:25–20:12, 21:04–21:21,
> 19:33–20:32, 18:24–18:33 — four distinct evening sessions the current plan renders as four
> indistinguishable date lines.

**Risk.** Scope creep into a stats tool. Keep the default plan to one extra column (the time
range) and put everything else behind `--summary`, or the plan stops being scannable at a
glance — which is currently its best quality.

---

### `feat-only-new`
**`--only-new`: remember what came off this card last time**

`Impact: medium` · `Effort: M` · `Verified: code-read`

Idempotence today is **destination-derived**: a file is "already imported" if a same-named
file of the same size exists at the destination. That is elegant, and it is why re-running is
free — but it breaks the moment you do the normal thing and move last week's day folders off
to an archive drive. fujimm then re-copies 200 GB it already has.

A small state file (`~/.local/state/fujimm/<volume-uuid>.json`) recording per card the last
import time and the set of `(basename, size, mtime)` — or the highest counter seen — plus
`--only-new` to scan against it. This also fixes the free-space false negative: the plan can
subtract known-imported bytes before the check.

**Risk.** This is the first persistent state the tool has ever kept, which is a real tension
with "no library, no catalogue". Mitigate by making it **opt-in**, keeping it **outside the
destination**, and making a missing or corrupt state file a silent no-op rather than an
error. Volume UUIDs are not among the keys `detectCards` currently requests, so that needs
adding — and a reformatted card getting a new identity is correct behaviour, not a bug.

---

### `feat-hooks`
**`--hook <command>` and shell completions**

`Impact: low` · `Effort: S` · `Verified: code-read`

There is no integration surface at all beyond exit codes and the one-line `--json`.

- **`--hook '<command>'`** run once after a clean import, with destination, day list, file
  count and byte count in the environment. That is how a photographer wires up "now start
  the Backblaze scan", "now open Capture One", "now post to the studio Slack" without fujimm
  needing to know about any of them.
- **zsh and bash completion** for the flag set, dropped next to the binary by `install.sh`.

**Security.** `--hook` executes a user-supplied string, so it must run via `execve` with an
argv array rather than a shell, must never run after a failed or interrupted import (guard
it exactly like `--eject`), and **must not be readable from any config file the tool picks
up implicitly** — flag only, or you have built a remote-execution vector into a tool that
reads removable media.

---

### `feat-log-file`
**`--log <path>` so a partial import can be diagnosed after the terminal scrolls away**

`Impact: medium` · `Effort: M` · `Verified: agent-reproduced`

When an import fails halfway, the user's only artefact is terminal text — which `--quiet`
suppresses entirely and `--json` omits. There is no log file, no per-file record, and no way
to ask "which files failed and why" after the fact. A plain re-run *does* retry the failures
(failed files were never created at the destination), but nothing tells the user that.

`--log <path>` writing one JSON object per line per file: source path, destination path,
outcome, bytes, sha256 when `--verify`, date source, error string. Plus the
`"failures":[{path,reason}]` array from
[`fix-scan-failures-invisible`](#fix-scan-failures-invisible).

**Risk.** Writing a log into the destination by default would surprise users who expect only
day folders. Keep it opt-in, or default it under `~/Library/Logs/fujimm/` rather than the
photo tree.

---

### `feat-contact-sheet`
**`--contact-sheet`: one self-contained HTML per day**

`Impact: medium` · `Effort: L` · `Verified: agent-reproduced`

After an import you have 131 files named after a counter and no way to see what is in them
without launching something. **Every RAF is a container with a full-size rendered JPEG
inside it** — with the film simulation applied — so a thumbnail costs a seek and a downscale,
not a RAW decode.

`<dest>/2026-08-05/contact-sheet.html`: a grid of ~400 px JPEGs as `data:` URIs, each
captioned with filename, time, lens, ISO, shutter, aperture and film sim, plus the day's
totals. One file, no assets folder, no server; opens in any browser and survives being
emailed. The natural companion to the manifest — the manifest is what a machine checks, the
contact sheet is what you check.

> Extraction verified end to end: the RAF header at offset 0x54/0x58 gives a JPEG
> offset/length pair; `dd` at that offset yields a valid `4416x2944` JPEG with intact EXIF.
> The literal magic `FUJIFILMCCD-RAW ` sits at byte 0 and the ASCII model at byte 28.

**Risk.** It makes fujimm a producer of **derived artifacts**, which is exactly the line the
README draws against Photos.app and Lightroom. Defensible only if the sheet is disposable,
single-file, and never referenced by anything else. Header offsets are RAF-version-specific
(`0201` on the X-T5 tested); fall back to ImageIO's thumbnail for anything that does not
parse, and skip HIF/MOV entirely rather than half-doing it. Base64 inflates the HTML ~33%, so
a 131-frame day at 400 px is roughly 10–15 MB — acceptable, but cap it and offer
`--contact-sheet-size`. **Rank it below everything above it**, because it is the first thing
fujimm would write that is not a copy of a file from the card.

---

### `feat-rename`
**`--rename` template that always keeps the original counter**

`Impact: medium` · `Effort: M` · `Verified: code-read` · *the weakest proposal here*

Filenames are preserved verbatim and collisions resolved with `-1`, `-2`. That is the right
default and should stay the default. But the Fuji counter wraps at 9999, and two bodies
shooting the same event both produce `DSCF6810.RAF` — so today the second body's frame
silently becomes `DSCF6810-1.RAF`, a name that tells you nothing and sorts adjacent to a
completely different frame.

`--rename '{date}_{orig}'` with `{body}`, `{model}`, `{counter}`, **constrained so the
template must contain `{orig}` or `{counter}`** — the tool refuses a template that discards
the camera's own identifier. That keeps the "same files" contract honest: the bytes are
unchanged and the frame is still findable by its counter, you have merely prefixed it.
Default stays off.

**Risk.** This is the proposal most in tension with the stated philosophy, and the one I
would defend least hard. Renamed files break external references — a Lightroom catalogue
pointing at `DSCF6810.RAF`, an `.xmp` whose name must be rewritten in lockstep, a client who
asked for "frame 6810". If it ships, it must rename every member of a stack consistently
([`feat-stacks`](#feat-stacks) is a hard prerequisite) and the manifest must record the
original name so the mapping is never lost.

**A cheaper 80% of the value:** leave names alone and just have `uniqueDestination` use the
body serial instead of `-1`, so a genuine cross-body collision becomes
`DSCF6810_4D011128.RAF`.

---

## Won't do

Explicit non-goals. Each is a real request with a real reason to decline.

### Card deletion / `--format` / `--delete-after-verify`

The most requested offload feature, and the answer is no.

**For:** it is the real end of the workflow. Every photographer eventually formats the card,
and doing it in a tool that just verified every byte is safer than doing it half-asleep in a
camera menu. Hedge and Photo Mechanic both offer it.

**Against, and this wins:** fujimm's trust proposition is **structural, not procedural** —
sources are `O_RDONLY`, there is no `unlink` or `rename` of a source anywhere in the binary,
and the run ends by printing *"The card was not modified."* The moment a delete path exists,
that sentence becomes a runtime claim rather than a property of the program, and a mis-parsed
flag, a `--yes` in shell history, or a `--source` pointed at the wrong folder can reach it.

The engineering argument for immediate verify-then-delete is also weak: **a card whose
controller is failing returns the same corrupted bytes on both reads**, so the checksum
matches and you format anyway. The failure you actually need to catch shows up days later.

**Instead:** ship [`feat-manifest-audit`](#feat-manifest-audit) and have
`fujimm --audit <dest> --against /Volumes/Untitled` print a blessing —
*"all 245 files on Untitled are present and byte-identical under ~/Documents/Fujifilm; safe
to format in-camera"* — and then stop. The user formats in the camera, which is correct
practice for card health and filesystem layout anyway, and which macOS's exFAT formatter does
not reproduce.

Note the strongest form of the argument: **there is currently no test target**, so there is
no automated way to prove a delete path stays unreachable.

### A launchd agent that imports on card insertion

The most-asked-for convenience, and it deletes the product. **The plan output is the
product** — it is the moment you notice the card has six weeks on it, that one day is
10.9 GB, or that a file is unreadable. A daemon replaces that moment with a notification you
will learn to ignore, and writes gigabytes to your disk on an event you did not initiate.
[`feat-hooks`](#feat-hooks) plus the existing exit codes lets anyone who genuinely wants it
build it in four lines of launchd plist, having opted in with their eyes open.

### A Linux port

See [`tech-no-linux-port`](#tech-no-linux-port). Four Darwin-only load-bearing dependencies,
one of which (EXIF from RAF) is the single most valuable thing the tool does. It is a second
product sharing a name.

### Homebrew bottles, and a signed/notarized `.pkg`

Both solve a problem this tool does not have. The build takes five seconds; source-building
via a tap sidesteps signing, notarization and Gatekeeper entirely. Revisit only if source
builds prove to be a real barrier. See [`tech-homebrew`](#tech-homebrew).

### CONTRIBUTING.md and SECURITY.md

For a zero-dependency, no-network tool with one maintainer, these are cargo cult. A *"PRs
welcome"* line in the README does the same work. **CHANGELOG.md is not in this bucket** — it
is the only channel through which users learn a data-loss bug was fixed.

### A film-simulation folder axis

`--film-sim` as a *filter* and a *report*, yes. Film simulation as a folder level, no. The
folder name is a date; that is the whole idea.

---

## Dependency chains

Real ordering constraints, by id.

```
fix-test-net
  └─► every fix in v1.1.0        (you cannot safely change the copy path without a net)
      └─► tech-run-type          (a pure mechanical move, pinned by the test)
          ├─► imp-plan-type
          ├─► imp-copy-overlap   (concurrency in the data path — net first, always)
          └─► imp-parallel-scan

fix-videodate-race
  ├─► tech-swift6                (it is the single blocking diagnostic)
  └─► imp-parallel-scan          (the semaphore-on-a-Task deadlocks under structured concurrency)

fix-silent-drop ─┬─► fix-rerun-duplicates    (both need one shared "is this the same file?" predicate)
                 └─► fix-symlink-size        (same predicate, fed a correct size)

feat-stacks
  ├─► feat-rename                (a stack must be renamed as a unit or the pairing breaks)
  └─► feat-last-day              (--newest N must count stacks, not files)

feat-manifest-audit
  ├─► feat-only-new              (the manifest is the state)
  ├─► imp-verify-double-hash     (verify against recorded digests, not a re-read)
  └─► the audit-blessing that replaces card deletion

tech-ci ─► tech-version-tag ─► tech-homebrew ─► tech-release-process
```

Two of these are worth restating because they are the ones most likely to be skipped:

- **`fix-test-net` genuinely comes first.** Not as a maturity ritual — two of its six
  assertions fail on `main` today, so writing it *is* how you find out whether the v1.1.0
  fixes worked.
- **`fix-silent-drop` and `fix-rerun-duplicates` are one piece of work.** Both hinge on the
  same question: *is this destination file the same file as this source file?* Answer it once,
  in one predicate, and both bugs close.

---

## Appendix: reproductions

Behaviours confirmed by hand against a real build in this session (`swift build`,
Apple Swift 6.3.3, macOS 26, synthetic fixture cards). Every one of these fails an
expectation the README sets.

| # | Command | Observed | Expected |
|---|---|---|---|
| 1 | Import; alter one dest file's size; re-run ×3 | `DSCF0001.JPG`, `-1`, `-2`, `-3` | "already there" after the first |
| 2 | Dest file same **size**, different bytes | `already there 1`, exit 0, dest SHA unchanged — **frame lost** | `DSCF0001-1.JPG` created |
| 3 | `--photos-dir '../../escape/PWNED'` | Files written two levels outside `--dest`, exit 0 | Argument rejected |
| 4 | `--tz EST` vs `--tz America/New_York`, July | `2026-07-03` vs `2026-07-04` | Same day, or `EST` rejected |
| 5 | `DSCF0002.RAF` (Jun 15) + `DSCF0002.XMP` (Aug 7) | Two different day folders | Both under `2026-06-15` |
| 6 | Symlinked source, 512 KB target | Plan says `115 B`; 3 runs → 3 copies | `500.0 KB`; 1 copy |
| 7 | `card/PRIVATE/AVCHD/BDMV/STREAM/00000.MTS` | Not imported, not reported | Imported or reported |
| 8 | `--json` with an unrecognised `.XYZ` present | `{"status":"ok",…}`, no mention | Reported per README |
| 9 | `fujimm … \| cat`, stderr on a tty | 0 bytes of progress | Progress on stderr |
| 10 | Planted `.fujimm-99999-*.part` | Survives every subsequent run | Swept or reported |
| 11 | Empty card | `Nothing to import.`, exit **1** | Exit 0 (nothing to do ≠ failure) |
| 12 | `--dry-run` on a 3-deep collision | "would be saved with a **-1** suffix" | `-4` |
| 13 | `--list --json`, no card | `{"status":"no-card","cards":[],…}` | Same shape as the with-card form |
| 14 | `swift build -Xswiftc -swift-version -Xswiftc 6` | Exactly 1 error, `DateResolver.swift:105` | — (this one is good news) |
| 15 | `grep -rn 'CoreServices\|DiskArbitration' Sources/` | 0 hits, both linked in `Package.swift` | — |
| 16 | `grep -rn '\.yes' Sources/` | Written once, read never | — |

---

*Generated from a multi-agent audit of fujimm v1.0.0. Findings marked `reproduced` were
re-tested by hand; see [Provenance and confidence](#provenance-and-confidence) for what that
does and does not cover — in particular, `Copier.swift` and the performance story warrant a
second dedicated pass.*
