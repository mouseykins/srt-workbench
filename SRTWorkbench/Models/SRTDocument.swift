import Foundation

enum SRTValidationError: LocalizedError {
    case invalidTimecodeFormat(cueIndex: Int)
    case endBeforeStart(cueIndex: Int)
    case overlappingCues(cueIndex: Int)
    case emptyText(cueIndex: Int)

    var errorDescription: String? {
        switch self {
        case .invalidTimecodeFormat(let i): return "Cue \(i + 1): Invalid timecode format"
        case .endBeforeStart(let i): return "Cue \(i + 1): End time must be after start time"
        case .overlappingCues(let i): return "Cue \(i + 1): Overlaps with previous cue"
        case .emptyText(let i): return "Cue \(i + 1): Text is empty"
        }
    }
}

@Observable
class SRTDocument {
    var cues: [SRTCue] = []
    var filePath: URL?

    /// Snapshot of cues at last save/load — dirty state is derived by comparison
    private var savedCues: [SRTCue] = []

    var isDirty: Bool {
        cues != savedCues
    }

    /// Call after saving to update the clean snapshot
    func markClean() {
        savedCues = cues
    }

    init() {}

    init(cues: [SRTCue], filePath: URL? = nil) {
        self.cues = cues
        self.filePath = filePath
        self.savedCues = cues
    }

    /// DCMP / CEA-608 compliance issues (advisory — these never block saving).
    func complianceViolations() -> [ComplianceViolation] {
        CaptionComplianceService.validate(cues)
    }

    func validate() -> [SRTValidationError] {
        var errors: [SRTValidationError] = []
        var previousEnd: TimeInterval = 0

        for (i, cue) in cues.enumerated() {
            if cue.endTime <= cue.startTime {
                errors.append(.endBeforeStart(cueIndex: i))
            }
            if cue.startTime < previousEnd {
                errors.append(.overlappingCues(cueIndex: i))
            }
            if cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyText(cueIndex: i))
            }
            previousEnd = cue.endTime
        }
        return errors
    }

    func save() throws {
        guard let path = filePath else {
            throw NSError(domain: "SRTDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file path set"])
        }
        let errors = validate()
        if let first = errors.first {
            throw first
        }
        let content = SRTParser.serialize(cues)
        try content.write(to: path, atomically: true, encoding: .utf8)
        markClean()
    }
}
