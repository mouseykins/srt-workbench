import Foundation

/// Transforms and validates cues against DCMP / CEA-608 caption standards.
///
/// `makeCompliant` rewraps cue text into ≤2 lines of ≤32 chars, splitting a cue
/// into several when its text is too long for one cue, and enforces the minimum
/// on-screen duration. When a strict split would produce sub-cues shorter than
/// `minDuration`, the line limit is relaxed to ≤45 chars for that cue only
/// before returning to strict rules for the next cue.
/// `validate` reports issues without mutating anything.
enum CaptionComplianceService {

    // MARK: - Constants

    /// Fallback line-length limit used only when splitting at the strict 32-char
    /// limit would produce sub-cues too short to meet `minDuration`.
    private static let relaxedMaxCharsPerLine = 45

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

            // Try the strict 32-char limit first.
            let strictChunks = splitIntoFittingChunks(words, maxCharsPerLine: CaptionCompliance.maxCharsPerLine)

            // If splitting at the strict limit would produce any sub-cue shorter
            // than minDuration, retry with the relaxed limit for this cue only.
            let useRelaxed = strictChunks.count > 1
                && wouldProduceShortCue(cue, chunks: strictChunks)
            let maxChars = useRelaxed ? relaxedMaxCharsPerLine : CaptionCompliance.maxCharsPerLine
            let chunks = useRelaxed
                ? splitIntoFittingChunks(words, maxCharsPerLine: relaxedMaxCharsPerLine)
                : strictChunks

            if chunks.count <= 1 {
                var newCue = cue
                newCue.text = wrap(words, maxCharsPerLine: maxChars)
                result.append(newCue)
            } else {
                result.append(contentsOf: splitCue(cue, into: chunks, maxCharsPerLine: maxChars))
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

    /// Returns `true` when proportionally splitting `cue` into `chunks` by
    /// character count would produce at least one sub-cue shorter than
    /// `CaptionCompliance.minDuration`.
    private static func wouldProduceShortCue(_ cue: SRTCue, chunks: [[String]]) -> Bool {
        let span = cue.endTime - cue.startTime
        let totalChars = Double(chunks.reduce(0) { $0 + charCount($1) })
        guard totalChars > 0 else { return false }
        return chunks.contains {
            span * Double(charCount($0)) / totalChars < CaptionCompliance.minDuration
        }
    }

    /// Greedily pack words into chunks where each chunk fits in ≤2 lines of
    /// `maxCharsPerLine`. An over-long single word becomes its own chunk
    /// (flagged later by `validate`).
    private static func splitIntoFittingChunks(
        _ words: [String],
        maxCharsPerLine: Int = CaptionCompliance.maxCharsPerLine
    ) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []

        for w in words {
            let trial = current + [w]
            if current.isEmpty || CaptionLineBreaker.canFit(trial, maxCharsPerLine: maxCharsPerLine) {
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
    private static func splitCue(
        _ cue: SRTCue,
        into chunks: [[String]],
        maxCharsPerLine: Int = CaptionCompliance.maxCharsPerLine
    ) -> [SRTCue] {
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
            subCues.append(SRTCue(startTime: start, endTime: end, text: wrap(chunk, maxCharsPerLine: maxCharsPerLine)))
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

    private static func wrap(
        _ words: [String],
        maxCharsPerLine: Int = CaptionCompliance.maxCharsPerLine
    ) -> String {
        let text = words.joined(separator: " ")
        if let lines = CaptionLineBreaker.breakIntoLines(text, maxCharsPerLine: maxCharsPerLine) {
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
