import Foundation

/// Terminal output helpers. Colour is emitted only when stdout is a tty and
/// NO_COLOR is unset, so piping to a file or another program stays clean.
enum Term {
    static let isTTY = isatty(fileno(stdout)) == 1
    static let useColor = isTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func c(_ code: String, _ s: String) -> String {
        useColor ? "\u{001B}[\(code)m\(s)\u{001B}[0m" : s
    }

    static func bold(_ s: String) -> String { c("1", s) }
    static func dim(_ s: String) -> String { c("2", s) }
    static func red(_ s: String) -> String { c("31", s) }
    static func green(_ s: String) -> String { c("32", s) }
    static func yellow(_ s: String) -> String { c("33", s) }
    static func blue(_ s: String) -> String { c("34", s) }
    static func cyan(_ s: String) -> String { c("36", s) }

    static var columns: Int {
        var w = winsize()
        if ioctl(fileno(stdout), TIOCGWINSZ, &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 80
    }

    /// Overwrite the current line. No-op when not a tty (avoids spraying \r into logs).
    static func status(_ s: String) {
        guard isTTY else { return }
        let max = columns - 1
        var line = s
        if line.count > max { line = String(line.prefix(max - 1)) + "…" }
        FileHandle.standardError.write("\r\u{001B}[2K\(line)".data(using: .utf8)!)
    }

    static func clearStatus() {
        guard isTTY else { return }
        FileHandle.standardError.write("\r\u{001B}[2K".data(using: .utf8)!)
    }

    static func err(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(n) B" : String(format: "%.1f %@", v, units[i])
    }

    static func rate(_ bytes: Int64, seconds: Double) -> String {
        guard seconds > 0.001 else { return "—" }
        return Self.bytes(Int64(Double(bytes) / seconds)) + "/s"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
