import AVFoundation
import AppKit
import Combine
import Foundation

@Observable
class ReviewViewModel {
    var document = SRTDocument()
    var videoURL: URL?
    var activeCueIndex: Int?
    var saveStatusMessage: String = ""
    var showSaveError = false
    var saveErrorMessage: String = ""
    var playbackSpeed: Double = 1.0

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
        } catch {
            saveStatusMessage = "Failed to load SRT: \(error.localizedDescription)"
        }
    }

    func loadVideo(from url: URL) {
        videoURL = url
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
        // isDirty is now computed automatically by comparing cues to savedCues
    }

    func updateCueEnd(at index: Int, timecode: String) {
        guard cues.indices.contains(index),
              let secs = TimecodeFormatter.seconds(from: timecode) else { return }
        document.cues[index].endTime = secs
        // isDirty is now computed automatically by comparing cues to savedCues
    }

    func updateCueText(at index: Int, text: String) {
        guard cues.indices.contains(index) else { return }
        document.cues[index].text = text
        // isDirty is now computed automatically by comparing cues to savedCues
    }

    // MARK: - Save

    func save() {
        let errors = document.validate()
        if let first = errors.first {
            saveErrorMessage = first.localizedDescription
            showSaveError = true
            return
        }

        do {
            try document.save()
            saveStatusMessage = "Saved \(document.cues.count) cues"
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
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
