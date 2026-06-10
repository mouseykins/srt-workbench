import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
class ReviewViewModel {
    var document = SRTDocument()
    var videoURL: URL?
    var activeCueIndex: Int?
    var saveStatusMessage: String = ""
    var showSaveError = false
    var saveErrorMessage: String = ""
    var playbackSpeed: Double = 1.0

    /// DCMP / CEA-608 issues, cached and recomputed when cues change rather
    /// than on every SwiftUI render.
    private(set) var complianceViolations: [ComplianceViolation] = []

    // Player is managed externally but we track time
    var currentTime: TimeInterval = 0 {
        didSet { updateActiveCue() }
    }

    var hasCues: Bool { !document.cues.isEmpty }
    var hasVideo: Bool { videoURL != nil }
    var isLoaded: Bool { hasCues && hasVideo }

    // MARK: - File Loading

    func loadSRT(from url: URL) {
        do {
            let cues = try SRTParser.parse(contentsOf: url)
            document = SRTDocument(cues: cues, filePath: url)
            saveStatusMessage = "Loaded \(cues.count) cues"
            log(.review, "loaded SRT: \(url.lastPathComponent) (\(cues.count) cues)")
        } catch {
            saveStatusMessage = "Failed to load SRT: \(error.localizedDescription)"
            logError(.review, "failed to load SRT \(url.path): \(error.localizedDescription)")
        }
        recomputeCompliance()
    }

    func loadVideo(from url: URL) {
        videoURL = url
        log(.review, "loaded video: \(url.lastPathComponent)")
    }

    // MARK: - File Pickers

    func pickVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Select Video"

        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(from: url)
        }
    }

    func pickSRTFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let srt = UTType(filenameExtension: "srt") {
            panel.allowedContentTypes = [srt]
        }
        panel.prompt = "Select SRT"

        if panel.runModal() == .OK, let url = panel.url {
            loadSRT(from: url)
        }
    }

    // MARK: - Cue Editing

    func updateCueStart(at index: Int, timecode: String) {
        guard cues.indices.contains(index),
              let secs = TimecodeFormatter.seconds(from: timecode) else { return }
        document.cues[index].startTime = secs
        recomputeCompliance()
    }

    func updateCueEnd(at index: Int, timecode: String) {
        guard cues.indices.contains(index),
              let secs = TimecodeFormatter.seconds(from: timecode) else { return }
        document.cues[index].endTime = secs
        recomputeCompliance()
    }

    func updateCueText(at index: Int, text: String) {
        guard cues.indices.contains(index) else { return }
        document.cues[index].text = text
        recomputeCompliance()
    }

    // MARK: - Compliance

    private func recomputeCompliance() {
        complianceViolations = document.complianceViolations()
    }

    /// Short multi-line summary of current formatting issues, for tooltips.
    var complianceSummary: String {
        let issues = complianceViolations
        guard !issues.isEmpty else { return "All cues are ADA/DCMP compliant" }
        var lines = issues.prefix(10).map { "Cue \($0.cueIndex + 1): \($0.message)" }
        if issues.count > lines.count {
            lines.append("… and \(issues.count - lines.count) more")
        }
        return lines.joined(separator: "\n")
    }

    /// Re-wrap every cue to ≤32-char lines, split over-long cues (by length
    /// and duration), and enforce minimum durations.
    func reflowForCompliance() {
        let before = complianceViolations.count
        document.cues = CaptionComplianceService.makeCompliant(document.cues)
        recomputeCompliance()
        let after = complianceViolations.count
        saveStatusMessage = "Reflowed \(document.cues.count) cues"
        log(.review, "reflow: \(before) -> \(after) compliance issues, \(document.cues.count) cues")
    }

    // MARK: - Save

    func save() {
        let errors = document.validate()
        if let first = errors.first {
            saveErrorMessage = first.localizedDescription
            showSaveError = true
            logWarn(.review, "save blocked by validation: \(first.localizedDescription)")
            return
        }

        do {
            try document.save()
            saveStatusMessage = "Saved \(document.cues.count) cues"
            log(.review, "saved \(document.cues.count) cues to \(document.filePath?.lastPathComponent ?? "?")")
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            logError(.review, "save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Active Cue Tracking

    var cues: [SRTCue] { document.cues }

    private func updateActiveCue() {
        let t = currentTime
        let newIndex = cues.firstIndex { t >= $0.startTime && t <= $0.endTime }
        if newIndex != activeCueIndex {
            activeCueIndex = newIndex
        }
    }

    /// Returns the text of the currently active cue (for caption overlay)
    var activeCueText: String? {
        guard let idx = activeCueIndex else { return nil }
        return cues[idx].text
    }

    func jumpToCue(at index: Int) -> TimeInterval? {
        guard cues.indices.contains(index) else { return nil }
        return cues[index].startTime
    }

    func togglePlaybackSpeed() {
        playbackSpeed = playbackSpeed == 1.0 ? 2.0 : 1.0
        NotificationCenter.default.post(
            name: .setPlaybackSpeed,
            object: nil,
            userInfo: ["speed": playbackSpeed]
        )
    }
}
