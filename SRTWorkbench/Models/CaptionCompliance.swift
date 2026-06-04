import Foundation

/// DCMP / CEA-608 caption-compliance constants.
///
/// These are the de facto accessibility-captioning limits (commonly referred to
/// when people ask for "ADA compliant" captions). The 32-character line
/// limit originates from the CEA-608 broadcast standard and is the most
/// conservative, widely-compatible target.
enum CaptionCompliance {
    /// Maximum characters per displayed line.
    static let maxCharsPerLine = 32
    /// Maximum number of lines per caption cue.
    static let maxLinesPerCue = 2
    /// Maximum characters per cue (derived: maxCharsPerLine × maxLinesPerCue).
    static let maxCharsPerCue = maxCharsPerLine * maxLinesPerCue
    /// Minimum on-screen duration, in seconds.
    static let minDuration: TimeInterval = 1.3
    /// Maximum on-screen duration, in seconds.
    static let maxDuration: TimeInterval = 6.0
    /// Target reading-speed floor, in words per minute.
    static let minWPM: Double = 130
    /// Target reading-speed ceiling, in words per minute.
    static let maxWPM: Double = 160
}

/// How serious a compliance issue is. Neither blocks saving — they are advisory.
enum ComplianceSeverity {
    case error    // hard formatting violation (line/lines limits)
    case warning  // timing / reading-speed guidance
}

/// A single compliance issue found on a specific cue.
struct ComplianceViolation: Identifiable, Equatable {
    enum Kind: Equatable {
        case lineTooLong(line: Int, charCount: Int)
        case tooManyLines(lineCount: Int)
        case durationTooShort(duration: TimeInterval)
        case durationTooLong(duration: TimeInterval)
        case readingSpeedTooFast(wpm: Double)
    }

    /// Zero-based index of the offending cue.
    let cueIndex: Int
    let kind: Kind

    var severity: ComplianceSeverity {
        switch kind {
        case .lineTooLong, .tooManyLines:
            return .error
        case .durationTooShort, .durationTooLong, .readingSpeedTooFast:
            return .warning
        }
    }

    /// Human-readable, 1-based description suitable for tooltips and lists.
    var message: String {
        switch kind {
        case let .lineTooLong(line, charCount):
            return "Cue \(cueIndex + 1): line \(line + 1) is \(charCount) chars (max \(CaptionCompliance.maxCharsPerLine))"
        case let .tooManyLines(lineCount):
            return "Cue \(cueIndex + 1): \(lineCount) lines (max \(CaptionCompliance.maxLinesPerCue))"
        case let .durationTooShort(duration):
            return String(format: "Cue \(cueIndex + 1): %.1fs on screen (min %.1fs)", duration, CaptionCompliance.minDuration)
        case let .durationTooLong(duration):
            return String(format: "Cue \(cueIndex + 1): %.1fs on screen (max %.1fs)", duration, CaptionCompliance.maxDuration)
        case let .readingSpeedTooFast(wpm):
            return String(format: "Cue \(cueIndex + 1): %.0f wpm reading speed (max %.0f)", wpm, CaptionCompliance.maxWPM)
        }
    }

    var id: String { "\(cueIndex)|\(message)" }
}
