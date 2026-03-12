import Foundation

enum SRTParser {
    private static let cueTimingPattern = #"^(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})$"#

    /// Parse SRT text into an array of cues
    static func parse(_ text: String) -> [SRTCue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var cues: [SRTCue] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            guard !lines.isEmpty else { continue }

            // Find the timing line — it's either lines[1] (with index on lines[0]) or lines[0]
            let timingLine: String
            let textStartIndex: Int

            if lines.count >= 2, lines[1].contains("-->") {
                timingLine = lines[1]
                textStartIndex = 2
            } else if lines[0].contains("-->") {
                timingLine = lines[0]
                textStartIndex = 1
            } else {
                continue
            }

            guard let match = timingLine.trimmingCharacters(in: .whitespaces)
                .range(of: cueTimingPattern, options: .regularExpression) else {
                continue
            }

            let matched = String(timingLine.trimmingCharacters(in: .whitespaces)[match])
            let parts = matched.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }

            let startTC = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")
            let endTC = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")

            guard let startSecs = TimecodeFormatter.seconds(from: startTC),
                  let endSecs = TimecodeFormatter.seconds(from: endTC) else {
                continue
            }

            let text = lines[textStartIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            cues.append(SRTCue(startTime: startSecs, endTime: endSecs, text: text))
        }

        return cues
    }

    /// Serialize cues to SRT format text
    static func serialize(_ cues: [SRTCue]) -> String {
        var lines: [String] = []
        for (idx, cue) in cues.enumerated() {
            lines.append(String(idx + 1))
            lines.append("\(cue.startTimecode) --> \(cue.endTimecode)")
            lines.append(cue.text.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        // Ensure single trailing newline
        let result = lines.joined(separator: "\n")
        return result.trimmingCharacters(in: .newlines) + "\n"
    }

    /// Parse SRT file at URL
    static func parse(contentsOf url: URL) throws -> [SRTCue] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return parse(text)
    }
}
