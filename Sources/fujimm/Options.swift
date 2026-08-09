import Foundation

struct Options {
    var destination: URL = Options.defaultDestination
    var sources: [String] = []
    var dryRun = false
    var listOnly = false
    var allCards = false
    var verify = false
    var overwrite = false
    var eject = false
    var json = false
    var quiet = false
    var verbose = false
    var flat = false
    var includeOther = false
    /// Overrides the refusal to eject a card that still holds content this run
    /// did not copy.
    var yes = false
    /// Restores the pre-1.1.0 behaviour of exiting 1 when there is nothing new
    /// to import, for scripts written against it.
    var failOnEmpty = false

    var dayFormat = "yyyy-MM-dd"
    var photosDirName = "Photos"
    var videosDirName = "Videos"
    var otherDirName = "Other"

    var onlyKind: MediaKind?
    var since: Date?
    var until: Date?
    var videoDatePolicy: VideoDatePolicy = .mtime
    var timeZone: TimeZone = .current

    static var defaultDestination: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("Fujifilm")
    }

    static let version = "1.0.0"
}

enum OptionsError: Error {
    case usage(String)
    case help
    case versionRequested
}

enum OptionsParser {

    static func parse(_ argv: [String]) throws -> Options {
        var o = Options()
        var i = 0

        func next(_ flag: String) throws -> String {
            i += 1
            guard i < argv.count else { throw OptionsError.usage("\(flag) needs a value") }
            return argv[i]
        }

        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "-h", "--help":     throw OptionsError.help
            case "--version":        throw OptionsError.versionRequested

            case "-d", "--dest", "--destination":
                let raw = try next(arg)
                // An unset shell variable turns `--dest "$DEST"` into `--dest ""`,
                // which Foundation resolves to the current directory — so a script
                // with a typo quietly imports 20 GB into wherever it was run.
                guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw OptionsError.usage("\(arg) needs a path")
                }
                o.destination = URL(
                    fileURLWithPath: (raw as NSString).expandingTildeInPath
                ).standardizedFileURL

            case "-s", "--source":
                o.sources.append(try next(arg))

            case "-n", "--dry-run":  o.dryRun = true
            case "-l", "--list":     o.listOnly = true
            case "--all-cards":      o.allCards = true
            case "--verify":         o.verify = true
            case "--overwrite":      o.overwrite = true
            case "--eject":          o.eject = true
            case "--fail-on-empty":  o.failOnEmpty = true
            case "--json":           o.json = true
            case "-q", "--quiet":    o.quiet = true
            case "-v", "--verbose":  o.verbose = true
            case "--flat":           o.flat = true
            case "--other":          o.includeOther = true
            case "-y", "--yes":      o.yes = true

            case "--date-format":    o.dayFormat = try dayFormat(try next(arg), flag: arg)
            case "--photos-dir":     o.photosDirName = try bucket(try next(arg), flag: arg)
            case "--videos-dir":     o.videosDirName = try bucket(try next(arg), flag: arg)
            case "--other-dir":      o.otherDirName = try bucket(try next(arg), flag: arg)

            case "--only":
                let v = try next(arg).lowercased()
                switch v {
                case "photo", "photos", "pictures", "images": o.onlyKind = .photo
                case "video", "videos", "movies":             o.onlyKind = .video
                default: throw OptionsError.usage("--only expects 'photos' or 'videos', got '\(v)'")
                }

            case "--since":
                o.since = try parseDay(try next(arg), endOfDay: false, tz: o.timeZone)
            case "--until":
                o.until = try parseDay(try next(arg), endOfDay: true, tz: o.timeZone)

            case "--video-date":
                let v = try next(arg).lowercased()
                guard let p = VideoDatePolicy(rawValue: v) else {
                    throw OptionsError.usage("--video-date expects 'mtime' or 'quicktime', got '\(v)'")
                }
                o.videoDatePolicy = p

            case "--timezone", "--tz":
                let v = try next(arg)
                guard let tz = TimeZone(identifier: v) ?? TimeZone(abbreviation: v) else {
                    throw OptionsError.usage("unknown timezone '\(v)'")
                }
                o.timeZone = tz

            default:
                if arg.hasPrefix("-") {
                    throw OptionsError.usage("unknown option '\(arg)'")
                }
                // A bare path is treated as a source, so `fujimm /Volumes/Untitled` works.
                o.sources.append(arg)
            }
            i += 1
        }

        // --since/--until were parsed before a later --timezone could apply; redo
        // them if the timezone was changed after they appeared.
        if o.timeZone != TimeZone.current {
            var j = 0
            while j < argv.count {
                if argv[j] == "--since", j + 1 < argv.count {
                    o.since = try parseDay(argv[j + 1], endOfDay: false, tz: o.timeZone)
                }
                if argv[j] == "--until", j + 1 < argv.count {
                    o.until = try parseDay(argv[j + 1], endOfDay: true, tz: o.timeZone)
                }
                j += 1
            }
        }

        if o.quiet && o.verbose {
            throw OptionsError.usage("--quiet and --verbose are mutually exclusive")
        }
        return o
    }

    /// A bucket name is interpolated straight into the per-item relative path,
    /// so `..` in it walks the destination out of the directory the user named —
    /// including back onto the card, while the run still prints "The card was
    /// not modified."
    ///
    /// `/` is allowed on purpose: `--photos-dir 'Raw/Fuji'` nests a bucket and
    /// works today. Only `..` escapes.
    private static func bucket(_ name: String, flag: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OptionsError.usage("\(flag) needs a folder name")
        }
        guard !PathSafety.containsUpwardComponent(name) else {
            throw OptionsError.usage("\(flag) cannot contain a '..' path component — got '\(name)'")
        }
        return name
    }

    /// DateFormatter passes `.` and `/` through as literals, so `--date-format
    /// '../..'` needs no quoting at all to escape the destination.
    ///
    /// The check has to be on the *output*, not the pattern: a quoted literal
    /// smuggles `..` past any inspection of the pattern itself — `yyyy'/../'MM`
    /// formats to `2026/../06`.
    private static func dayFormat(_ pattern: String, flag: String) throws -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        let rendered = f.string(from: Date(timeIntervalSince1970: 1_781_524_800))

        guard !rendered.isEmpty else {
            throw OptionsError.usage("\(flag) '\(pattern)' produces an empty folder name")
        }
        guard !PathSafety.containsUpwardComponent(rendered) else {
            throw OptionsError.usage(
                "\(flag) '\(pattern)' produces '\(rendered)', which contains a '..' path component"
            )
        }
        return pattern
    }

    private static func parseDay(_ s: String, endOfDay: Bool, tz: TimeZone) throws -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        for pattern in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyyMMdd", "yyyy:MM:dd"] {
            f.dateFormat = pattern
            if let d = f.date(from: s) {
                return endOfDay ? d.addingTimeInterval(24 * 3600 - 1) : d
            }
        }
        throw OptionsError.usage("cannot read date '\(s)' — expected YYYY-MM-DD")
    }

    static let helpText = """
    \(Term.bold("fujimm")) — sort a Fujifilm card into per-day Photos/Videos folders.

    \(Term.bold("USAGE"))
      fujimm [options]              detect the card and import
      fujimm --list                 show detected cards, import nothing
      fujimm /path/to/folder        import from an explicit folder

    Copy-only. fujimm opens every source file read-only and never writes to,
    renames or deletes anything on the card.

    \(Term.bold("OUTPUT LAYOUT"))
      <destination>/
        2026-06-15/
          Photos/   DSCF6810.RAF …
          Videos/   DSCF6809.MOV …
        2026-07-19/
          Photos/ …
          Videos/ …

    \(Term.bold("OPTIONS"))
      -d, --dest <path>       Destination root
                              (default: ~/Documents/Fujifilm)
      -s, --source <path>     Import from this volume or folder instead of
                              auto-detecting. Repeatable.
      -n, --dry-run           Show exactly what would be copied, copy nothing
      -l, --list              List detected cards and exit
          --all-cards         Import from every detected card, not just one

          --only <kind>       'photos' or 'videos' only
          --since <date>      Skip media before this day (YYYY-MM-DD)
          --until <date>      Skip media after this day (YYYY-MM-DD)

          --date-format <f>   Day-folder format (default yyyy-MM-dd).
                              Examples: 'yyyy/MM/dd', 'yyyy-MM-dd EEEE'
          --photos-dir <name> Rename the Photos subfolder (default Photos)
          --videos-dir <name> Rename the Videos subfolder (default Videos)
          --flat              No Photos/Videos split — one folder per day
          --other             Also copy unrecognised file types into Other/

          --verify            SHA-256 every copy against its source
          --overwrite         Replace same-named files that differ
                              (default: keep both, adding -1, -2, …)
          --video-date <src>  'mtime' (default) or 'quicktime'
          --tz <zone>         Timezone for day grouping (default: system)

          --eject             Eject the card after a clean import
          -y, --yes           Eject even when a filter left files on the card
          --fail-on-empty     Exit 1 when there is nothing new to import
                              (the default is 0 — nothing to do is not a failure)
          --json              Machine-readable summary on stdout
      -v, --verbose           Per-file detail, including the date source
      -q, --quiet             Errors only
      -h, --help              This help
          --version           Version

    \(Term.bold("HOW THE DAY IS DECIDED"))
      Photos  EXIF DateTimeOriginal — the camera's own clock, no timezone
              conversion, so the folder matches the day you actually shot.
      Videos  File modification time, which on a Fujifilm exFAT card
              reproduces the camera clock and matches what Finder shows.
              Use --video-date quicktime to read the container metadata.

    \(Term.bold("EXAMPLES"))
      fujimm                                    import the card to ~/Documents/Fujifilm
      fujimm -n                                 preview first
      fujimm -d ~/Pictures/Iceland              import somewhere specific
      fujimm --only photos --since 2026-08-01   just the recent stills
      fujimm --verify --eject                   checksum everything, then eject
    """
}
