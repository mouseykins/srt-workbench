import Foundation

enum TimecodeFormatter {
    /// Convert seconds to SRT timecode "HH:MM:SS,mmm".
    /// Rounds to whole milliseconds first so 59.9996 becomes "00:01:00,000"
    /// rather than the invalid "00:00:59,1000".
    static func string(from seconds: TimeInterval) -> String {
        let totalMs = max(0, Int((seconds * 1000).rounded()))
        let h = totalMs / 3_600_000
        let m = (totalMs % 3_600_000) / 60_000
        let s = (totalMs % 60_000) / 1000
        let ms = totalMs % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// Parse SRT timecode "HH:MM:SS,mmm" to seconds. Returns nil on invalid format.
    static func seconds(from timecode: String) -> TimeInterval? {
        let pattern = #"^(\d{2}):(\d{2}):(\d{2}),(\d{3})$"#
        guard let match = timecode.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let str = String(timecode[match])
        let parts = str.components(separatedBy: CharacterSet(charactersIn: ":,"))
        guard parts.count == 4,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              let s = Int(parts[2]),
              let ms = Int(parts[3]) else {
            return nil
        }
        return TimeInterval(h * 3600 + m * 60 + s) + TimeInterval(ms) / 1000.0
    }

    /// Validate that a string is a valid SRT timecode
    static func isValid(_ timecode: String) -> Bool {
        seconds(from: timecode) != nil
    }
}
