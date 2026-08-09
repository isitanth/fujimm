import Foundation

/// What bucket a file lands in once imported.
enum MediaKind: String {
    case photo
    case video
    case other
}

enum Formats {
    /// Still-image formats a Fujifilm body (or the X-App / in-camera RAW converter)
    /// can put on a card, plus the generic ones worth accepting.
    ///
    /// - `raf`  Fujifilm RAW — every X and GFX body
    /// - `hif`  10-bit HEIF — X-H2 / X-H2S / X-T5 / X-S20 / GFX100 II
    /// - `mpo`  stereo pair — FinePix REAL 3D W1 / W3
    /// - `tif`  in-camera TIFF — GFX and older FinePix
    /// - `dng`  not a native X-series output, but produced by instax / X-App / tethering
    static let photoExtensions: Set<String> = [
        "RAF",
        "JPG", "JPEG", "JPE",
        "HIF", "HEIF", "HEIC", "HEICS",
        "TIF", "TIFF",
        "MPO",
        "DNG",
        "PNG",
        "BMP",
        "AVIF",
        "WEBP",
    ]

    /// Movie formats. X-series records `.MOV` (H.264 / HEVC / ProRes); the
    /// X-A, X-T200 and HS lines record `.MP4`; `.AVI` and `.3GP` come from
    /// older FinePix compacts; `.MTS`/`.M2TS` are AVCHD from mixed-brand cards.
    static let videoExtensions: Set<String> = [
        "MOV", "QT",
        "MP4", "M4V",
        "AVI",
        "MTS", "M2TS",
        "3GP", "3G2",
        "MPG", "MPEG",
        "MKV",
    ]

    /// Files that belong with a media file rather than standing on their own.
    /// They follow whatever their basename resolved to.
    static let sidecarExtensions: Set<String> = ["XMP", "THM", "LRV", "AAE", "CTG"]

    /// Directories that live on a Fujifilm card but never hold user media.
    /// `FFDB` is the camera's own image database, `UPD` is the firmware staging
    /// folder, the rest are macOS/Windows bookkeeping.
    static let ignoredDirectories: Set<String> = [
        "FFDB", "UPD", "MISC", "PRIVATE",
        ".SPOTLIGHT-V100", ".TRASHES", ".FSEVENTSD", ".TEMPORARYITEMS",
        "SYSTEM VOLUME INFORMATION", "$RECYCLE.BIN", ".DOCUMENTREVISIONS-V100",
    ]

    static func kind(forExtension ext: String) -> MediaKind {
        let e = ext.uppercased()
        if photoExtensions.contains(e) { return .photo }
        if videoExtensions.contains(e) { return .video }
        return .other
    }

    static func isSidecar(_ ext: String) -> Bool {
        sidecarExtensions.contains(ext.uppercased())
    }

    /// macOS writes AppleDouble resource-fork stubs (`._DSCF1234.RAF`) onto
    /// exFAT cards the moment they're browsed in Finder. There are 18 of them on
    /// a card that has merely been opened. They are never user media.
    static func isJunk(_ filename: String) -> Bool {
        if filename.hasPrefix("._") { return true }
        if filename == ".DS_Store" { return true }
        if filename.hasPrefix(".") { return true }
        return false
    }
}
