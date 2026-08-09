import Foundation

// MARK: - Entry

let rawArgs = Array(CommandLine.arguments.dropFirst())

let options: Options
do {
    options = try OptionsParser.parse(rawArgs)
} catch OptionsError.help {
    print(OptionsParser.helpText)
    exit(0)
} catch OptionsError.versionRequested {
    print("fujimm \(Options.version)")
    exit(0)
} catch OptionsError.usage(let message) {
    Term.err("\(Term.red("error:")) \(message)")
    Term.err("Try 'fujimm --help'.")
    exit(2)
} catch {
    Term.err("\(Term.red("error:")) \(error.localizedDescription)")
    exit(2)
}

Copier.installSignalHandlers()

// MARK: - Find the card

var cards: [Card] = []

if options.sources.isEmpty {
    let detected = Volumes.detectCards()
    if detected.isEmpty {
        if options.json {
            print(#"{"status":"no-card","cards":[],"imported":0}"#)
        } else {
            Term.err("No camera card found.")
            Term.err("")
            Term.err("Insert an SD card, or point fujimm at a folder:")
            Term.err("  fujimm --source /path/to/DCIM")
        }
        exit(1)
    }
    // --list is the command you reach for *because* several cards are inserted,
    // so it always reports all of them rather than demanding you disambiguate.
    if detected.count == 1 || options.allCards || options.listOnly {
        cards = detected
    } else {
        // More than one candidate: take the single Fujifilm one if that's
        // unambiguous, otherwise make the user choose rather than guessing.
        let fuji = detected.filter { $0.isFujifilm }
        if fuji.count == 1 {
            cards = fuji
            if !options.quiet {
                let others = detected.filter { !$0.isFujifilm }.map(\.name).joined(separator: ", ")
                Term.err(Term.dim("Ignoring non-Fujifilm card(s): \(others)"))
            }
        } else {
            Term.err("Several cards are inserted — pick one with --source, or use --all-cards:")
            for c in detected {
                Term.err("  \(c.volumeURL.path)   \(c.displayName)")
            }
            exit(2)
        }
    }
} else {
    for s in options.sources {
        guard let c = Volumes.card(forPath: s) else {
            Term.err("\(Term.red("error:")) not a readable folder: \(s)")
            exit(2)
        }
        cards.append(c)
    }
}

// MARK: - --list

if options.listOnly {
    if options.json {
        let entries = cards.map { c in
            """
            {"path":\(jsonString(c.volumeURL.path)),"name":\(jsonString(c.name)),\
            "fujifilm":\(c.isFujifilm),"dcim":\(jsonString(c.dcimURL.path)),\
            "capacity":\(c.totalCapacity),"free":\(c.availableCapacity)}
            """
        }
        print("{\"cards\":[\(entries.joined(separator: ","))]}")
    } else {
        print(Term.bold("Detected \(cards.count) card\(cards.count == 1 ? "" : "s"):"))
        for c in cards {
            let cap = c.totalCapacity > 0
                ? "  \(Fmt.bytes(c.totalCapacity - c.availableCapacity)) used of \(Fmt.bytes(c.totalCapacity))"
                : ""
            print("  \(Term.cyan(c.volumeURL.path))")
            print("    name      \(c.displayName)")
            print("    dcim      \(c.dcimURL.path)")
            print("    removable \(c.isRemovable ? "yes" : "no")\(cap)")
        }
    }
    exit(0)
}

// MARK: - Safety: don't import a card into itself

for c in cards {
    // Containment, not volume identity. For a real card the two coincide, but
    // `--source ~/old-offload` makes the "card" a folder on the user's own
    // disk, where the destination is legitimately on the same volume — the
    // advertised re-sort workflow. What must be refused is a destination inside
    // the source tree.
    //
    // isContained resolves symlinks and case through realpath, so it also
    // closes the three defects in the string comparison this replaces. It fails
    // closed, which for a refusal check means an undeterminable answer allows
    // the import; every individual write is containment-checked regardless.
    if PathSafety.isContained(options.destination.path, in: c.volumeURL.path) {
        Term.err("\(Term.red("error:")) destination is inside the card (\(options.destination.path)).")
        Term.err("Choose a destination on your Mac with --dest.")
        exit(2)
    }
}

// MARK: - Scan

let resolver = DateResolver(dayFormat: options.dayFormat,
                            videoPolicy: options.videoDatePolicy,
                            timeZone: options.timeZone)
let scanner = Scanner(options: options, resolver: resolver)

var scans: [(Card, ScanResult)] = []
for c in cards {
    if !options.quiet && !options.json {
        Term.status("Scanning \(c.displayName)…")
    }
    scans.append((c, scanner.scan(card: c)))
}
Term.clearStatus()

let allItems = scans.flatMap { $0.1.items }
let totalBytes = allItems.reduce(Int64(0)) { $0 + $1.size }

if allItems.isEmpty {
    if options.json {
        print(#"{"schemaVersion":1,"status":"nothing-to-import","imported":0,"failed":0}"#)
    } else {
        print("Nothing to import.")
        for (c, s) in scans where !s.unknownExtensions.isEmpty {
            let exts = s.unknownExtensions.sorted { $0.value > $1.value }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            print(Term.dim("  \(c.name): unrecognised file types present — \(exts) (use --other to copy them)"))
        }
    }
    // "Everything is already safe" is not a failure. This used to share exit 1
    // with "I could not find your card", so a launchd job or a shell pipeline
    // written as `fujimm --json && post-process` treated a fully-imported card
    // as an error. --fail-on-empty restores the old behaviour for anyone who
    // was relying on it.
    exit(options.failOnEmpty ? 1 : 0)
}

// MARK: - Plan

if !options.quiet && !options.json {
    for (c, _) in scans {
        print(Term.bold("Card ") + Term.cyan(c.volumeURL.path)
              + Term.dim("  \(c.isFujifilm ? "Fujifilm" : "generic DCIM")"))
    }
    print(Term.bold("Destination ") + Term.cyan(options.destination.path))
    print("")

    // Per-day tree, exactly the shape that will be created.
    var byDay: [String: (photos: Int, videos: Int, other: Int, bytes: Int64)] = [:]
    for item in allItems {
        var e = byDay[item.date.day] ?? (0, 0, 0, 0)
        switch item.kind {
        case .photo: e.photos += 1
        case .video: e.videos += 1
        case .other: e.other += 1
        }
        e.bytes += item.size
        byDay[item.date.day] = e
    }

    let days = byDay.keys.sorted()
    print(Term.bold("\(days.count) day\(days.count == 1 ? "" : "s"), \(allItems.count) files, \(Fmt.bytes(totalBytes))"))
    for day in days {
        let e = byDay[day]!
        print("  \(Term.blue(day))  \(Term.dim(Fmt.bytes(e.bytes)))")
        if options.flat {
            let n = e.photos + e.videos + e.other
            print("    \(n) file\(n == 1 ? "" : "s")")
        } else {
            if e.photos > 0 { print("    \(options.photosDirName)/  \(e.photos)") }
            if e.videos > 0 { print("    \(options.videosDirName)/  \(e.videos)") }
            if e.other > 0 { print("    \(options.otherDirName)/  \(e.other)") }
        }
    }
    print("")

    for (c, s) in scans {
        if s.skippedJunk > 0 && options.verbose {
            print(Term.dim("  \(c.name): skipped \(s.skippedJunk) macOS metadata file(s)"))
        }
        if !s.unknownExtensions.isEmpty && !options.includeOther {
            let exts = s.unknownExtensions.sorted { $0.value > $1.value }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            print(Term.yellow("  not importing unrecognised types: ") + exts
                  + Term.dim("  (use --other to include them)"))
        }
        // Unreadable entries are reported once, on stderr, after the run — see
        // the failure block at the end. Printing them here too would duplicate
        // them in text mode.
    }
}

// MARK: - Free space check

if !options.dryRun {
    let destParent = options.destination
    let probe = FileManager.default.fileExists(atPath: destParent.path)
        ? destParent
        : destParent.deletingLastPathComponent()
    // volumeAvailableCapacityForImportantUsage is the better number on APFS —
    // it counts space macOS would free by evicting purgeable files — but it
    // reports 0 on exFAT, and exFAT is exactly what a cross-platform archive
    // drive is formatted as. Taking it at face value refused every import to
    // one. Fall back to the plain key, and if neither yields a figure, let the
    // copy proceed and fail on ENOSPC rather than refusing on no evidence.
    let capacityKeys: Set<URLResourceKey> = [
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey,
    ]
    if let v = try? probe.resourceValues(forKeys: capacityKeys) {
        let important = v.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(v.volumeAvailableCapacity ?? 0)
        let free = important > 0 ? important : plain
        if free > 0 && free < totalBytes {
            Term.err("\(Term.red("error:")) not enough space at \(options.destination.path).")
            Term.err("  need \(Fmt.bytes(totalBytes)), free \(Fmt.bytes(free))")
            exit(2)
        }
    }
}

// MARK: - Copy

let copier = Copier(options: options)
var records: [CopyRecord] = []
var copiedBytes: Int64 = 0
var doneBytes: Int64 = 0
let start = Date()

if !options.dryRun {
    do {
        try FileManager.default.createDirectory(at: options.destination,
                                                withIntermediateDirectories: true)
    } catch {
        Term.err("\(Term.red("error:")) cannot create \(options.destination.path) — \(error.localizedDescription)")
        exit(2)
    }
}

for (index, item) in allItems.enumerated() {
    if copier.interrupted { break }

    let label = "[\(index + 1)/\(allItems.count)] \(item.relativeDestination)"
    if !options.quiet && !options.json {
        let elapsed = Date().timeIntervalSince(start)
        let pct = totalBytes > 0 ? Int(Double(doneBytes) * 100 / Double(totalBytes)) : 0
        Term.status("\(pct)%  \(label)  \(Fmt.rate(doneBytes, seconds: elapsed))")
    }

    let record = copier.copy(item, toRoot: options.destination) { chunk in
        doneBytes += chunk
        if !options.quiet && !options.json && item.size > 64 * 1024 * 1024 {
            let elapsed = Date().timeIntervalSince(start)
            let pct = totalBytes > 0 ? Int(Double(doneBytes) * 100 / Double(totalBytes)) : 0
            let remaining = elapsed > 0 && doneBytes > 0
                ? Double(totalBytes - doneBytes) / (Double(doneBytes) / elapsed)
                : 0
            Term.status("\(pct)%  \(label)  \(Fmt.rate(doneBytes, seconds: elapsed))  ETA \(Fmt.duration(remaining))")
        }
    }
    records.append(record)

    switch record.outcome {
    // A renamed file was written in full — its bytes belong in the total, the
    // throughput figure and the JSON just as much as a plain copy's.
    case .copied(let b), .overwritten(let b), .renamed(_, let b):
        copiedBytes += b
    case .skippedIdentical, .wouldCopy:
        // Skipped and planned items still advance the byte counter for ETA purposes.
        doneBytes += item.size
    case .failed, .interrupted:
        break
    }

    if options.verbose && !options.json {
        Term.clearStatus()
        print(describe(record))
    }
}
Term.clearStatus()

// MARK: - Summary

let elapsed = Date().timeIntervalSince(start)
var copiedCount = 0, skippedCount = 0, renamedCount = 0, failedCount = 0, plannedCount = 0
var plannedBytes: Int64 = 0, renamedBytes: Int64 = 0
var failures: [CopyRecord] = []

for r in records {
    switch r.outcome {
    case .copied, .overwritten: copiedCount += 1
    case .skippedIdentical:     skippedCount += 1
    case .renamed:              renamedCount += 1; renamedBytes += r.item.size
    case .wouldCopy:            plannedCount += 1; plannedBytes += r.item.size
    case .failed:               failedCount += 1; failures.append(r)
    case .interrupted:          break
    }
}

let wasInterrupted = copier.interrupted

// Everything the run did NOT copy. These were previously reachable only in text
// mode: a scripted `fujimm --json` saw {"status":"ok"} for a run that left an
// unreadable folder full of photographs on the card.
let unreadable = scans.flatMap { $0.1.unreadable }
let unknownExtensions = scans.reduce(into: [String: Int]()) { acc, entry in
    for (ext, n) in entry.1.unknownExtensions { acc[ext, default: 0] += n }
}

if options.json {
    let days = Set(allItems.map { $0.date.day }).sorted()
    let failureObjects = failures.map { r -> String in
        guard case .failed(let why) = r.outcome else { return "{}" }
        return "{\"path\":\(jsonString(r.item.source.path)),\"reason\":\(jsonString(why))}"
    }
    let unreadableObjects = unreadable.map {
        "{\"path\":\(jsonString($0.0.path)),\"reason\":\(jsonString($0.1))}"
    }
    let unknownObjects = unknownExtensions.sorted { $0.key < $1.key }
        .map { "\(jsonString($0.key)):\($0.value)" }
    print("""
    {"schemaVersion":1,\
    "status":\(jsonString(wasInterrupted ? "interrupted"
                          : (failedCount > 0 || !unreadable.isEmpty ? "partial" : "ok"))),\
    "dryRun":\(options.dryRun),\
    "destination":\(jsonString(options.destination.path)),\
    "days":[\(days.map { jsonString($0) }.joined(separator: ","))],\
    "scanned":\(allItems.count),\
    "copied":\(copiedCount),"renamed":\(renamedCount),"skipped":\(skippedCount),\
    "planned":\(plannedCount),"failed":\(failedCount),\
    "bytes":\(copiedBytes),"plannedBytes":\(plannedBytes),\
    "failures":[\(failureObjects.joined(separator: ","))],\
    "unreadable":[\(unreadableObjects.joined(separator: ","))],\
    "unknownExtensions":{\(unknownObjects.joined(separator: ","))},\
    "seconds":\(String(format: "%.2f", elapsed))}
    """)
} else if !options.quiet {
    print("")
    if options.dryRun {
        print(Term.bold("Dry run — nothing was copied."))
        print("  would copy    \(plannedCount) file\(plannedCount == 1 ? "" : "s")  (\(Fmt.bytes(plannedBytes)))")
        if skippedCount > 0 { print("  already there \(skippedCount)") }
        if renamedCount > 0 {
            // Not a hardcoded "-1": the fourth collision on a name lands as -4,
            // and saying otherwise made the dry run mispredict the real run.
            let example = records.compactMap { r -> String? in
                if case .renamed(let to, _) = r.outcome { return to }
                return nil
            }.first
            let suffix = example.map { ", e.g. \($0)" } ?? ""
            print("  name clashes  \(renamedCount) (\(Fmt.bytes(renamedBytes)), kept alongside\(suffix))")
        }
    } else {
        if wasInterrupted {
            print(Term.yellow("Interrupted — the partial file was removed. Re-run to resume."))
        }
        print(Term.bold("Done in \(Fmt.duration(elapsed))"))
        print("  copied        \(Term.green("\(copiedCount)")) file\(copiedCount == 1 ? "" : "s")  (\(Fmt.bytes(copiedBytes)) at \(Fmt.rate(copiedBytes, seconds: elapsed)))")
        if skippedCount > 0 { print("  already there \(skippedCount)") }
        if renamedCount > 0 { print("  kept both     \(renamedCount) (same name, different content)") }
        if failedCount > 0  { print("  \(Term.red("failed        \(failedCount)"))") }
        print("  destination   \(Term.cyan(options.destination.path))")
    }

    print("")
    print(Term.dim("The card was not modified."))
}

// On stderr, and in every output mode. `--help` describes --quiet as "errors
// only", and a scripted --json run that left photographs behind must not look
// like a clean one. stderr keeps it out of the JSON a caller is parsing.
for r in failures {
    if case .failed(let why) = r.outcome {
        Term.err(Term.red("  ✗ ") + r.item.relativeDestination + Term.dim(" — \(why)"))
    }
}
for (url, why) in unreadable {
    Term.err(Term.yellow("  unreadable: ") + url.path + Term.dim(" — \(why)"))
}

// MARK: - Eject

if options.eject && !options.dryRun && failedCount == 0 && !wasInterrupted {
    for c in cards where c.isRemovable {
        if Volumes.eject(c) {
            if !options.quiet && !options.json { print("Ejected \(c.name).") }
        } else if !options.quiet {
            Term.err(Term.yellow("Could not eject \(c.name) — something may still be using it."))
        }
    }
}

if wasInterrupted { exit(130) }

// An unreadable directory means photographs are still on the card. Scanner
// collects those into ScanResult.unreadable and keeps walking, but they never
// became MediaItems, never became CopyRecords, and so never reached
// failedCount — an entire unreadable DCIM subfolder used to yield exit 0.
exit(failedCount > 0 || !unreadable.isEmpty ? 3 : 0)

// MARK: - Helpers

/// Quote and escape a string for `--json`. Volume names and destination paths
/// are user data and may legally contain `"` or `\`, which would otherwise
/// produce a document no parser accepts.
func jsonString(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 {
                out += String(format: "\\u%04X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out + "\""
}

func describe(_ r: CopyRecord) -> String {
    let src = Term.dim("[\(r.item.date.source.rawValue)]")
    switch r.outcome {
    case .copied(let b):
        return "  \(Term.green("✓")) \(r.item.relativeDestination)  \(Fmt.bytes(b)) \(src)"
    case .overwritten(let b):
        return "  \(Term.yellow("↻")) \(r.item.relativeDestination)  \(Fmt.bytes(b)) overwritten \(src)"
    case .skippedIdentical:
        return "  \(Term.dim("·")) \(r.item.relativeDestination)  \(Term.dim("already imported"))"
    case .renamed(let to, _):
        return "  \(Term.yellow("+")) \(r.item.relativeDestination)  \(Term.dim("saved as \(to)"))"
    case .wouldCopy:
        return "  \(Term.dim("→")) \(r.item.relativeDestination)  \(Fmt.bytes(r.item.size)) \(src)"
    case .failed(let why):
        return "  \(Term.red("✗")) \(r.item.relativeDestination)  \(Term.red(why))"
    case .interrupted:
        return "  \(Term.yellow("⊘")) \(r.item.relativeDestination)  interrupted"
    }
}
