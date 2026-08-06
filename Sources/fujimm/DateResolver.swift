import Foundation
import ImageIO
import AVFoundation

/// Where a file's shoot-day came from, so `--verbose` and `--json` can show it.
enum DateSource: String {
    case exifOriginal   = "EXIF:DateTimeOriginal"
    case exifDigitized  = "EXIF:DateTimeDigitized"
    case tiffDateTime   = "TIFF:DateTime"
    case quickTime      = "QuickTime:creationDate"
    case fileModified   = "file:mtime"
    case fileCreated    = "file:birthtime"
}

struct ResolvedDate {
    var day: String        // already formatted, e.g. "2026-06-15"
    var instant: Date?     // best-effort absolute time, for --since/--until and sorting
    var source: DateSource
}

/// How to date a movie file.
enum VideoDatePolicy: String {
    /// Filesystem modification time rendered in the display timezone. On the
    /// exFAT cards Fujifilm writes, this reproduces the camera's own wall clock
    /// and matches exactly what Finder shows.
    case mtime
    /// Ask AVFoundation for the container creation date. Correct for files that
    /// have been through other software, but Fujifilm's `mvhd` atom does not
    /// agree with the camera clock, so it is not the default.
    case quicktime
}

final class DateResolver {
    private let dayFormatter: DateFormatter
    private let videoPolicy: VideoDatePolicy
    private let timeZone: TimeZone

    /// Parses the EXIF `yyyy:MM:dd HH:mm:ss` form. EXIF carries no timezone, so
    /// this is anchored to the display timezone purely to produce a comparable
    /// `Date`; the folder name is taken from the literal digits and never
    /// undergoes a timezone conversion.
    private let exifParser: DateFormatter

    init(dayFormat: String, videoPolicy: VideoDatePolicy, timeZone: TimeZone) {
        self.videoPolicy = videoPolicy
        self.timeZone = timeZone

        dayFormatter = DateFormatter()
        dayFormatter.dateFormat = dayFormat
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone

        exifParser = DateFormatter()
        exifParser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exifParser.locale = Locale(identifier: "en_US_POSIX")
        exifParser.timeZone = timeZone
    }

    func resolve(url: URL, kind: MediaKind, attributes: [FileAttributeKey: Any]) -> ResolvedDate {
        switch kind {
        case .photo:
            if let r = photoDate(url) { return r }
        case .video:
            if videoPolicy == .quicktime, let r = videoDate(url) { return r }
        case .other:
            break
        }
        return filesystemDate(attributes)
    }

    // MARK: - Photos

    private func photoDate(_ url: URL) -> ResolvedDate? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let candidates: [(String?, DateSource)] = [
            (exif?[kCGImagePropertyExifDateTimeOriginal] as? String, .exifOriginal),
            (exif?[kCGImagePropertyExifDateTimeDigitized] as? String, .exifDigitized),
            (tiff?[kCGImagePropertyTIFFDateTime] as? String, .tiffDateTime),
        ]

        for (raw, source) in candidates {
            guard let raw, let parsed = exifParser.date(from: raw) else { continue }
            // Use the parsed Date so a custom --date-format (e.g. "yyyy/MM-MMMM/dd")
            // works, but because the parser and the formatter share one timezone
            // the calendar day always equals the literal EXIF digits.
            return ResolvedDate(day: dayFormatter.string(from: parsed),
                                instant: parsed,
                                source: source)
        }
        return nil
    }

    // MARK: - Videos

    private func videoDate(_ url: URL) -> ResolvedDate? {
        let asset = AVURLAsset(url: url)
        var result: Date?
        let sem = DispatchSemaphore(value: 0)
        Task {
            if let item = try? await asset.load(.creationDate),
               let d = try? await item.load(.dateValue) {
                result = d
            }
            sem.signal()
        }
        // Metadata reads on a card are quick; bail out rather than hang a batch.
        _ = sem.wait(timeout: .now() + 10)

        guard let d = result else { return nil }
        return ResolvedDate(day: dayFormatter.string(from: d), instant: d, source: .quickTime)
    }

    // MARK: - Filesystem fallback

    private func filesystemDate(_ attributes: [FileAttributeKey: Any]) -> ResolvedDate {
        if let m = attributes[.modificationDate] as? Date {
            return ResolvedDate(day: dayFormatter.string(from: m), instant: m, source: .fileModified)
        }
        if let c = attributes[.creationDate] as? Date {
            return ResolvedDate(day: dayFormatter.string(from: c), instant: c, source: .fileCreated)
        }
        let now = Date()
        return ResolvedDate(day: dayFormatter.string(from: now), instant: now, source: .fileModified)
    }
}
