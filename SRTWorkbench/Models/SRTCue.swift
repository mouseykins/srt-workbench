import Foundation

struct SRTCue: Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    var startTimecode: String {
        get { TimecodeFormatter.string(from: startTime) }
        set {
            if let secs = TimecodeFormatter.seconds(from: newValue) {
                startTime = secs
            }
        }
    }

    var endTimecode: String {
        get { TimecodeFormatter.string(from: endTime) }
        set {
            if let secs = TimecodeFormatter.seconds(from: newValue) {
                endTime = secs
            }
        }
    }

    var duration: TimeInterval { endTime - startTime }

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }

    init?(startTimecode: String, endTimecode: String, text: String) {
        guard let start = TimecodeFormatter.seconds(from: startTimecode),
              let end = TimecodeFormatter.seconds(from: endTimecode) else {
            return nil
        }
        self.id = UUID()
        self.startTime = start
        self.endTime = end
        self.text = text
    }
}

// MARK: - Caption compliance helpers

extension SRTCue {
    /// The cue's displayed lines (split on newlines).
    var lines: [String] { text.components(separatedBy: "\n") }

    /// Number of displayed lines.
    var lineCount: Int { lines.count }

    /// Character count of the longest line.
    var maxLineLength: Int { lines.map(\.count).max() ?? 0 }
}
