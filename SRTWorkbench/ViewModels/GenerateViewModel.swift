import AppKit
import Foundation

@Observable
class GenerateViewModel {
    var mediaDirectory: URL?
    var selectedVideo: URL?
    var selectedScript: URL?
    var alignmentService = AlignmentService()
    var errorMessage: String?
    var showError = false

    // Text filter toggles
    var filterStageDirections = true
    var filterSlideNumbers = true
    var customFilterPatternsText = ""

    /// Patterns that remove entire lines when the full line matches.
    var activeFilterPatterns: [String] {
        var patterns: [String] = []
        if filterStageDirections {
            patterns.append(#"^\[.*\]$"#)
        }
        let custom = customFilterPatternsText
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        patterns.append(contentsOf: custom)
        return patterns
    }

    /// Patterns that strip inline matches from text (keeping the rest of the line).
    var activeStripPatterns: [String] {
        var patterns: [String] = []
        if filterSlideNumbers {
            patterns.append(#"\(\d+\)"#)
            patterns.append(#"^\d+:\s*"#)
        }
        return patterns
    }

    static let videoExtensions = Set(["mp4", "mov", "mkv", "webm", "m4v"])
    static let scriptExtensions = Set(["docx"])

    var availableVideos: [URL] {
        guard let dir = mediaDirectory else { return [] }
        return Self.scanFiles(in: dir, extensions: Self.videoExtensions)
    }

    var availableScripts: [URL] {
        guard let dir = mediaDirectory else { return [] }
        return Self.scanFiles(in: dir, extensions: Self.scriptExtensions)
    }

    var isRunning: Bool {
        if case .running = alignmentService.state { return true }
        return false
    }

    var canRun: Bool {
        selectedVideo != nil && selectedScript != nil && !isRunning
    }

    func pickMediaDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose media directory containing videos and scripts"

        if let dir = mediaDirectory {
            panel.directoryURL = dir
        }

        if panel.runModal() == .OK, let url = panel.url {
            mediaDirectory = url
            selectedVideo = nil
            selectedScript = nil
        }
    }

    func pickVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Select Video"

        if panel.runModal() == .OK {
            selectedVideo = panel.url
        }
    }

    func pickScriptFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Script"

        if panel.runModal() == .OK {
            selectedScript = panel.url
        }
    }

    func runAlignment() async {
        guard let video = selectedVideo, let script = selectedScript else { return }

        errorMessage = nil

        do {
            // Output directory: ./srt subfolder in media dir (or video dir)
            let baseDir = mediaDirectory ?? video.deletingLastPathComponent()
            let outputDir = baseDir.appendingPathComponent("srt")
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            // Python parses the .docx using python-docx (handles xml:space correctly)
            let srtURL = try await alignmentService.runAlignment(
                videoURL: video,
                docxURL: script,
                outputDir: outputDir,
                filterPatterns: activeFilterPatterns,
                stripPatterns: activeStripPatterns
            )

            // Post-process for DCMP/CEA-608 compliance: wrap to ≤32-char lines,
            // split over-long cues, and enforce minimum durations.
            if let rawCues = try? SRTParser.parse(contentsOf: srtURL) {
                let compliant = CaptionComplianceService.makeCompliant(rawCues)
                let serialized = SRTParser.serialize(compliant)
                try? serialized.write(to: srtURL, atomically: true, encoding: .utf8)
            }

            // Post notification so Review tab can pick it up.
            // Dispatch to MainActor so ReviewViewModel state mutations happen on the main thread.
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .alignmentCompleted,
                    object: nil,
                    userInfo: ["srtURL": srtURL, "videoURL": video]
                )
            }

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            alignmentService.state = .failed(error.localizedDescription)
        }
    }

    // MARK: - File Scanning

    private static func scanFiles(in directory: URL, extensions: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if extensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}

extension Notification.Name {
    static let alignmentCompleted = Notification.Name("alignmentCompleted")
}
