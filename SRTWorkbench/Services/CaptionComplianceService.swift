import Foundation

/// Transforms and validates cues against DCMP / CEA-608 caption standards.
///
/// `makeCompliant` rewraps cue text into ≤2 lines of ≤32 chars, splitting a cue
/// into several when its text is too long for one cue, and enforces the minimum
/// on-screen duration. `validate` reports issues without mutating anything.
enum CaptionComplianceService {

    // MARK: - Transformation

    /// Return a compliant copy of `cues`: rewrapped lines, split over-long cues,
    /// and minimum durations enforced.
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

        enforceMinDuration(&result)
        return result
    }

    // MARK: - Validation

    /// Report all compliance violations in `cues` without changing them.
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

            let duration = cue.duration
            if duration < CaptionCompliance.minDuration {
                violations.append(ComplianceViolation(cueIndex: i, kind: .durationTooShort(duration: duration)))
            } else if duration > CaptionCompliance.maxDuration {
                violations.append(ComplianceViolation(cueIndex: i, kind: .durationTooLong(duration: duration)))
            }

            if cue.wordsPerMinute > CaptionCompliance.maxWPM {
                violations.append(ComplianceViolation(cueIndex: i, kind: .readingSpeedTooFast(wpm: cue.wordsPerMinute)))
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

    /// Extend any sub-minimum-duration cue up to the floor, without overlapping
    /// the cue that follows.
    private static func enforceMinDuration(_ cues: inout [SRTCue]) {
        for i in cues.indices where cues[i].duration < CaptionCompliance.minDuration {
            var newEnd = cues[i].startTime + CaptionCompliance.minDuration
            if i + 1 < cues.count {
                newEnd = min(newEnd, cues[i + 1].startTime)
            }
            if newEnd > cues[i].endTime {
                cues[i].endTime = newEnd
            }
        }
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
