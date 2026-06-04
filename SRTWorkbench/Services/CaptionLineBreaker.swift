import Foundation

/// Linguistically-aware line breaker for captions.
///
/// Breaks a run of text into at most `maxLines` lines of at most `maxCharsPerLine`
/// characters each, preferring break points that don't split grammatical units
/// (articles + nouns, prepositions + objects, names, numbers + units, etc.).
enum CaptionLineBreaker {

    // MARK: - Word lists (lowercased, punctuation-stripped)

    /// Words that should not be left dangling at the END of a line — they bind
    /// tightly to whatever follows, so breaking right after them reads badly.
    private static let avoidTrailing: Set<String> = [
        // articles
        "a", "an", "the",
        // conjunctions
        "and", "but", "or", "nor", "so", "yet", "for",
        // prepositions
        "of", "in", "on", "at", "to", "by", "up", "as", "off", "out", "via", "per",
        "from", "with", "into", "onto", "over", "under", "upon",
        "about", "above", "across", "after", "among", "around",
        "before", "behind", "below", "beneath", "beside", "between",
        "beyond", "during", "inside", "near", "since", "through",
        "toward", "towards", "until", "within", "without", "against",
        // auxiliaries / modals
        "is", "are", "was", "were", "be", "been", "being", "am",
        "will", "would", "shall", "should", "can", "could",
        "may", "might", "must", "do", "does", "did", "have", "has", "had",
        // determiners / possessives that bind to a noun
        "my", "your", "his", "her", "its", "our", "their",
        "this", "that", "these", "those", "some", "any", "no",
        "each", "every", "either", "neither",
        // intensifiers / comparatives
        "very", "really", "quite", "rather", "more", "most", "less", "least", "too",
        // misc binders
        "not", "if", "than", "then",
    ]

    // MARK: - Public API

    /// Break `text` into up to `maxLines` lines, each ≤ `maxCharsPerLine`.
    ///
    /// Returns `nil` when the text has more than one word and cannot fit — the
    /// caller should split the cue. A single word longer than the limit is
    /// returned as one (over-length) line rather than failing.
    static func breakIntoLines(_ text: String,
                               maxCharsPerLine: Int = CaptionCompliance.maxCharsPerLine,
                               maxLines: Int = CaptionCompliance.maxLinesPerCue) -> [String]? {
        let normalized = normalize(text)
        if normalized.isEmpty { return [""] }

        let words = normalized.split(separator: " ").map(String.init)

        // Already fits on a single line.
        if normalized.count <= maxCharsPerLine {
            return [normalized]
        }
        // A single over-long word — best effort, one line.
        if words.count == 1 {
            return [normalized]
        }
        // The common case: choose the single best break point for two lines.
        if maxLines == 2 {
            return bestTwoLineBreak(words, maxCharsPerLine: maxCharsPerLine)
        }
        // General fallback for other line counts.
        let greedy = greedyPack(words, maxCharsPerLine: maxCharsPerLine)
        return greedy.count <= maxLines ? greedy : nil
    }

    /// Whether `words` can be packed into ≤ `maxLines` lines of ≤ `maxCharsPerLine`.
    static func canFit(_ words: [String],
                       maxCharsPerLine: Int = CaptionCompliance.maxCharsPerLine,
                       maxLines: Int = CaptionCompliance.maxLinesPerCue) -> Bool {
        if words.isEmpty { return true }
        // A word longer than a whole line can never be placed within the limit.
        if words.contains(where: { $0.count > maxCharsPerLine }) { return false }
        return greedyPack(words, maxCharsPerLine: maxCharsPerLine).count <= maxLines
    }

    // MARK: - Two-line break selection

    private static func bestTwoLineBreak(_ words: [String], maxCharsPerLine: Int) -> [String]? {
        var best: (score: Double, lines: [String])?

        for i in 0..<(words.count - 1) {
            let line1 = words[0...i].joined(separator: " ")
            let line2 = words[(i + 1)...].joined(separator: " ")
            if line1.count > maxCharsPerLine || line2.count > maxCharsPerLine { continue }

            let score = breakScore(prevWord: words[i],
                                   nextWord: words[i + 1],
                                   line1Len: line1.count,
                                   line2Len: line2.count)
            if best == nil || score > best!.score {
                best = (score, [line1, line2])
            }
        }

        return best?.lines
    }

    /// Score a candidate break that ends line 1 with `prevWord` and starts
    /// line 2 with `nextWord`. Higher is better.
    private static func breakScore(prevWord: String,
                                   nextWord: String,
                                   line1Len: Int,
                                   line2Len: Int) -> Double {
        var score = 0.0

        // Prefer balanced line lengths.
        score -= Double(abs(line1Len - line2Len)) * 0.5

        let prev = clean(prevWord)

        // Don't leave a binding word dangling at the end of line 1.
        if avoidTrailing.contains(prev) {
            score -= 40
        }
        // Don't split a likely proper-noun pair ("Martin Keen").
        if isCapitalized(prevWord) && isCapitalized(nextWord) {
            score -= 15
        }
        // Don't split a number from the word it quantifies ("16 megabytes").
        if isNumeric(prev) {
            score -= 20
        }
        // Strongly prefer breaking right after clause/sentence punctuation.
        if let last = prevWord.last, ",;:.!?—".contains(last) {
            score += 25
        }

        return score
    }

    // MARK: - Greedy packing (feasibility + fallback)

    /// First-fit line packing. For a fixed word order this yields the minimum
    /// possible number of lines, which makes it a correct feasibility test.
    private static func greedyPack(_ words: [String], maxCharsPerLine: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for w in words {
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= maxCharsPerLine {
                current += " " + w
            } else {
                lines.append(current)
                current = w
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Lowercase and strip leading/trailing punctuation for word-list matching.
    private static func clean(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func isCapitalized(_ word: String) -> Bool {
        word.first?.isUppercase ?? false
    }

    private static func isNumeric(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isNumber }
    }
}
