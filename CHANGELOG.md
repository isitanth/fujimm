# Changelog

## 1.1.1

Minor change fixes.

## 1.1.0

### If you are using 1.0.0, please read this

**1.0.0 could silently discard a photograph.** When a file on the card had the
same name and the same size as one already at the destination, fujimm treated it
as already imported: it was never copied, never renamed, and never mentioned.
The run reported it under "already there" and exited 0.

This was not a rare edge case for Fujifilm cards. Counters wrap at `DSCF9999`
and restart, a second body reuses the same `DSCF####` names, and uncompressed
RAF is a fixed byte size for a given body — so same name, same size, different
photograph is the *normal* case when two cards merge into one day folder.

**What to do.** If you have ever imported two cards, or two bodies, into the
same day folder, and you still have the original cards, re-import them with
1.1.0 and compare the file counts. Frames that were dropped will appear this
time with a `-1` suffix. If the cards have been formatted, the affected frames
are not recoverable and nothing in this release can bring them back.

Passing `--verify` avoided the bug in 1.0.0, because it compared checksums
instead of sizes.

### Fixed — data loss

- A destination file with the same name and size as the source is no longer
  treated as already imported. Identity is now decided by size, modification
  time within two seconds, and a SHA-256 of the first and last 64 KB — a full
  hash of both sides under `--verify`. Anything not provably identical is kept
  alongside rather than skipped.
- Re-running after a name collision no longer adds another `-N` copy every time.
  `DSCF0001-1.JPG` is now recognised on the next run instead of becoming `-2`,
  then `-3`. Exhausting all 9999 slots is a reported failure rather than a
  silent skip.
- A symlinked source is no longer re-copied on every run. The scanner stated
  the link rather than its target, so the recorded size was the length of the
  link's path — reachable through the documented `fujimm --source ~/old-offload`
  workflow.

### Fixed — writing outside the destination

- `--photos-dir`, `--videos-dir`, `--other-dir` and `--date-format` can no
  longer contain a `..` path component. Previously `--photos-dir '../..'` wrote
  files outside `--dest`, including back onto the card, while the summary still
  printed "The card was not modified."
- Every write is checked against the destination root immediately beforehand,
  and directories are created without following symlinks — a symlink planted
  inside the destination could previously redirect the write outside it.
- `--dest ""` is rejected. An unset shell variable used to import into the
  current working directory.
- The "don't import a card into itself" guard now resolves symlinks and case
  correctly. It previously compared raw paths, so a symlink into the card passed
  and a case variant on APFS or exFAT was not recognised.

### Fixed — the output tells the truth

- `--json` reports `failures`, `unreadable` and `unknownExtensions`. A scripted
  run could previously see `{"status":"ok"}` for an import that left an
  unreadable folder full of photographs on the card.
- Failures and unreadable folders are written to stderr in every output mode,
  including `--quiet`, which `--help` already described as "errors only".
- The JSON summary carries `"schemaVersion": 1`.
- Renamed files' bytes are counted in the byte total, the throughput figure and
  the JSON `bytes` field. They were written in full but reported as zero.
- `--dry-run` names the destination the real run will use, instead of always
  claiming a `-1` suffix.
- Importing to an **exFAT** destination works. The free-space check read a
  capacity key that reports 0 on exFAT, so every import to a cross-platform
  archive drive failed with "not enough space, free 0 B".

### Changed — please check your scripts

- **A run with nothing new to import now exits 0, not 1.** It shared exit 1 with
  "no card found", so `fujimm --json && post-process` treated a fully-imported
  card as a failure. Pass `--fail-on-empty` for the old behaviour.
- **An unreadable folder now exits 3.** It means photographs are still on the
  card; it previously exited 0.
- **`--eject` refuses when the card still holds content this run did not copy** —
  after `--only`, `--since`/`--until`, an unreadable folder, or unrecognised
  types skipped without `--other`. `fujimm --only photos --eject` used to leave
  every video on the card and eject it anyway. Pass `-y` to override.
- `-y/--yes` now does something. It was accepted and read nowhere.

### Added

- `--fail-on-empty`.
- A test suite, and CI running it on macOS. 31 tests, including one that hashes
  the whole card tree before and after a real import and requires it to be
  byte-identical — the README's central claim, previously verified by nothing.

## 1.0.0

First release.
