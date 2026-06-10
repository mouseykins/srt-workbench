import Foundation

/// DCMP / CEA-608 caption-formatting constants.
///
/// These are the de facto accessibility-captioning limits (commonly referred to
/// when people ask for "ADA compliant" captions). The 32-character line
/// limit originates from the CEA-608 broadcast standard and is the most
/// conservative, widely-compatible target.
///
/// Only formatting is validated — timing qualities like reading speed or
/// on-screen duration follow from the speaker's actual pace, which this tool
/// has no control over, so they are not reported as violations.
enum CaptionCompliance {
    /// Maximum characters per displayed line.
    static let maxCharsPerLine = 32
    /// Maximum number of lines per caption cue.
    static let maxLinesPerCue = 2
    /// Maximum characters per cue (derived: maxCharsPerLine × maxLinesPerCue).
    static let maxCharsPerCue = maxCharsPerLine * maxLinesPerCue
}

/// A single formatting issue found on a specific cue. All issues are fixable
/// by Reflow; none block saving.
struct ComplianceViolation: Identifiable, Equatable {
    enum Kind: Equatable {
        case lineTooLong(line: Int, charCount: Int)
        case tooManyLines(lineCount: Int)
    }

    /// Zero-based index of the offending cue.
    let cueIndex: Int
    let kind: Kind

    /// Human-readable, 1-based description suitable for tooltips and lists.
    var message: String {
        switch kind {
        case let .lineTooLong(line, charCount):
            return "Line \(line + 1) is \(charCount) chars (max \(CaptionCompliance.maxCharsPerLine))"
        case let .tooManyLines(lineCount):
            return "\(lineCount) lines (max \(CaptionCompliance.maxLinesPerCue))"
        }
    }

    var id: String { "\(cueIndex)|\(message)" }
}
