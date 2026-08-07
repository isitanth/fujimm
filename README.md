# fujimm (fuji media manager)

Current feature is to sort a Fujifilm card into per-day folders over a simple CLI command.

```
fujimm
```

---

## Why

A Fujifilm card places everything at one flat folder:

```
/Volumes/Untitled/DCIM/100_FUJI/
    DSCF6803.RAF  DSCF6804.RAF  DSCF6807.MOV  DSCF6810.RAF  …  ×245
```

Two hundred files named after a counter, six weeks of shooting, stills and clips
mixed.

The obvious ways out are all slightly wrong:

- **Photos.app / Lightroom** import your files into a catalogue and then own
  them. Fine until you want the originals back as plain folders.
- **Image Capture** copies the card, flat, into one directory. You still have to
  sort it.
- **Dragging in Finder** and sorting by date is the trap: on an exFAT card
  Finder's *Date Created* is not the capture date, and it silently writes 18
  `._DSCF*` AppleDouble stubs onto your card the moment you open it.

It was boring for me and needed a simple cleaner and non-destructive solution.

## The outcome

```console
$ fujimm
Card /Volumes/Untitled  Fujifilm
Destination ~/Documents/Fujifilm

6 days, 245 files, 20.7 GB
  2026-06-15  1.5 GB
    Photos/  8
    Videos/  4
  2026-07-19  2.9 GB
    Photos/  18
    Videos/  14
  2026-07-27  135.2 MB
    Videos/  1
  2026-08-03  2.8 GB
    Photos/  35
  2026-08-04  2.5 GB
    Photos/  31
  2026-08-05  10.9 GB
    Photos/  131
    Videos/  3

27%  [60/245] 2026-08-03/Photos/DSCF6892.RAF  123.7 MB/s  ETA 2m 4s
```

```
~/Documents/Fujifilm/
├── 2026-06-15/
│   ├── Photos/    DSCF6803.RAF  DSCF6804.RAF  …
│   └── Videos/    DSCF6807.MOV  DSCF6808.MOV  …
├── 2026-07-19/
│   ├── Photos/
│   └── Videos/
├── 2026-07-27/
│   └── Videos/
└── 2026-08-05/
    ├── Photos/
    └── Videos/
```

Look before you leap with `fujimm --dry-run`, which prints exactly the tree above
and copies nothing.

## Install

```bash
git clone https://github.com/isitanth/fujimm.git
cd fujimm
./install.sh
```

Builds a release binary and puts it on your `PATH`. macOS 13+, Swift 5.9+, no
dependencies — `swift build` works offline and links only against system
frameworks.

## Use

```bash
fujimm                                   # detect the card, import it
fujimm --dry-run                         # show the plan, copy nothing
fujimm --list                            # what cards can you see?
fujimm --dest ~/Pictures/Iceland         # somewhere else
fujimm --only photos --since 2026-08-01  # just this month's stills
fujimm --verify --eject                  # checksum every copy, then eject
fujimm --flat                            # one folder per day, no Photos/Videos
fujimm --date-format 'yyyy/MM/dd'        # year/month/day nesting
fujimm --source ~/old-offload            # re-sort a folder you already copied
```

`fujimm --help` lists everything.

## Context

**Videos are dated by modification time, on purpose.** Fujifilm cards are exFAT,
which stores wall-clock time, so mtime reproduces the camera's own clock and
matches what Finder shows. The QuickTime container date does *not*: on this card
`DSCF6807.MOV` carries an `mvhd` creation date of 07:13:02 against a camera clock
of 06:12:38 — an hour out, enough to push a late-evening clip onto the wrong day.
`--video-date quicktime` switches to it anyway for footage that has been through
other software.

*Tested on a real X-T5 card: across all 223 RAF files, the EXIF day and the
modification-time day agreed on every single one.*

**The card is read-only, structurally.** Sources are opened `O_RDONLY`; there is
no code path in this tool that writes to, renames or unlinks a file on the card.
Everything else follows from that:

- Each file is streamed to a temporary `.part` **in the destination** and renamed
  into place only once complete, so an interrupted run never leaves a truncated
  file wearing a real name. Ctrl-C is safe; re-run to resume.
- Already-imported files are detected by size — by SHA-256 under `--verify` — and
  skipped, so re-running costs nothing.
- An existing destination file is never clobbered. Same name, different bytes
  means the new copy lands beside it as `DSCF6803-1.RAF`. `--overwrite` opts out.
- The camera's timestamps are carried onto the copies, so the sorted tree still
  sorts by capture time.
- `FFDB/` and `UPD/` (the camera's own database and firmware folders) and the
  `._*` stubs are skipped. Unrecognised extensions are *reported*, never silently
  dropped; `--other` copies them into `Other/`.

## Formats

| | |
|---|---|
| **Photos** | `RAF` `JPG` `JPEG` `JPE` `HIF` `HEIF` `HEIC` `TIF` `TIFF` `MPO` `DNG` `PNG` `BMP` `AVIF` `WEBP` |
| **Videos** | `MOV` `MP4` `M4V` `AVI` `MTS` `M2TS` `3GP` `3G2` `MPG` `MPEG` `MKV` `QT` |
| **Sidecars** | `XMP` `THM` `LRV` `AAE` `CTG` — follow whichever file shares their basename |

Covers Fujifilm RAW from every X and GFX body, the 10-bit `HIF` files from the
X-H2 / X-T5 / X-S20 / GFX100 II, in-camera TIFF from the GFX line, and the `MPO`
stereo pairs from the FinePix REAL 3D bodies. X-series bodies record `.MOV`; the
X-A, X-T200 and HS lines record `.MP4`; `.AVI` and `.3GP` come from older FinePix
compacts.

## Project structure

```
Sources/fujimm/
├── main.swift           entry point — plan, copy loop, summary, exit codes
├── Options.swift        argument parsing and the help text
├── Volumes.swift        card detection, Fujifilm signature, eject
├── Scanner.swift        walks DCIM, classifies, filters, builds destination paths
├── DateResolver.swift   EXIF / QuickTime / mtime → the day a file belongs to
├── Copier.swift         streaming copy, SHA-256 verify, collision handling
├── Formats.swift        extension tables
└── Term.swift           tty colour, byte / rate / duration formatting
Package.swift            no dependencies; system frameworks only
install.sh               swift build -c release, then put it on your PATH
```

About 1,450 lines of Swift. `Scanner` decides *what* and *where*, `Copier` decides
*how* — they share nothing but the `MediaItem` struct, so either can be read on
its own.

## Exit codes

| Code | Meaning |
|-----:|---------|
| `0` | Success |
| `1` | No card found, or nothing to import |
| `2` | Bad arguments, not enough space, or unsafe destination |
| `3` | Finished, but some files failed |
| `130` | Interrupted with Ctrl-C |

`--json` prints a single-line machine-readable summary for scripting.

## License

[MIT](LICENSE)
