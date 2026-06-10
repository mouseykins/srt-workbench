import Foundation

/// Transforms and validates cue text against DCMP / CEA-608 formatting limits.
///
/// `makeCompliant` rewraps cue text into ≤2 lines of ≤32 chars, splitting a cue
/// into several when its text is too long for one cue. `validate` reports
/// issues without mutating anything. Timing (duration, reading speed) is
/// deliberately not validated — it follows from the speaker's pace.
enum CaptionComplianceService {

    // MARK: - Transformation

    /// Return a compliant copy of `cues`: rewrapped lines, with over-long
    /// cues split across multiple cues (time divided proportionally to text).
    static func makeCompliant(_ cues: [SRTCue]) -> [SRTCue] {
        var result: [SRTCue] = []

        for cue in cues {
            let words = normalizeWhitespace(cue.text).split(separator: " ").map(String.init)

            guard !words.isEmpty else {
                result.append(cue)
                continue
            }

            let chunks = splitIntoFittingChunks(words)

            if chunks.count <= 1 {
                var newCue = cue
                newCue.text = wrap(words)
                result.append(newCue)
            } else {
                result.append(contentsOf: splitCue(cue, into: chunks))
            }
        }

        return result
    }

    // MARK: - Validation

    /// Report all formatting violations in `cues` without changing them.
    static func validate(_ cues: [SRTCue]) -> [ComplianceViolation] {
        var violations: [ComplianceViolation] = []

        for (i, cue) in cues.enumerated() {
            let lines = cue.lines

            if lines.count > CaptionCompliance.maxLinesPerCue {
                violations.append(ComplianceViolation(cueIndex: i, kind: .tooManyLines(lineCount: lines.count)))
            }
            for (li, line) in lines.enumerated() where line.count > CaptionCompliance.maxCharsPerLine {
                violations.append(ComplianceViolation(cueIndex: i, kind: .lineTooLong(line: li, charCount: line.count)))
            }
        }

        return violations
    }

    // MARK: - Splitting helpers

    /// Greedily pack words into chunks where each chunk fits in ≤2 lines of ≤32.
    /// An over-long single word becomes its own chunk (flagged later by `validate`).
    private static func splitIntoFittingChunks(_ words: [String]) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []

        for w in words {
            let trial = current + [w]
            if current.isEmpty || CaptionLineBreaker.canFit(trial) {
                current = trial
            } else {
                chunks.append(current)
                current = [w]
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Split one cue's time span across `chunks`, proportional to character count.
    private static func splitCue(_ cue: SRTCue, into chunks: [[String]]) -> [SRTCue] {
        let totalChars = chunks.reduce(0) { $0 + charCount($1) }
        guard totalChars > 0 else { return [cue] }

        let span = cue.endTime - cue.startTime
        var subCues: [SRTCue] = []
        var cursor = cue.startTime

        for (idx, chunk) in chunks.enumerated() {
            let isLast = idx == chunks.count - 1
            let portion = span * Double(charCount(chunk)) / Double(totalChars)
            let start = cursor
            let end = isLast ? cue.endTime : cursor + portion
            cursor = end
            subCues.append(SRTCue(startTime: start, endTime: end, text: wrap(chunk)))
        }
        return subCues
    }

    // MARK: - Text helpers

    private static func wrap(_ words: [String]) -> String {
        let text = words.joined(separator: " ")
        if let lines = CaptionLineBreaker.breakIntoLines(text) {
            return lines.joined(separator: "\n")
        }
        return text
    }

    private static func charCount(_ words: [String]) -> Int {
        words.joined(separator: " ").count
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
