import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
class GenerateViewModel {
    var mediaDirectory: URL? {
        didSet {
            refreshFileLists()
            UserDefaults.standard.set(mediaDirectory?.path, forKey: Keys.mediaDirectory)
        }
    }
    var selectedVideo: URL? {
        didSet { loadVideoDuration() }
    }
    var selectedScript: URL?
    var alignmentService = AlignmentService()
    var errorMessage: String?
    var showError = false

    /// "14:32" — duration of the selected video, loaded asynchronously.
    var videoDurationText: String?

    // Script-extraction preview sheet
    var showScriptPreview = false
    var isLoadingPreview = false
    var previewHeading: String?
    var previewLines: [String] = []

    // Cached directory scans — recomputed on directory change or refresh, NOT
    // on every SwiftUI render (scanning is recursive and can be slow).
    private(set) var availableVideos: [URL] = []
    private(set) var availableScripts: [URL] = []

    // Text filter toggles (persisted)
    var filterStageDirections: Bool {
        didSet { UserDefaults.standard.set(filterStageDirections, forKey: Keys.filterStageDirections) }
    }
    var filterSlideNumbers: Bool {
        didSet { UserDefaults.standard.set(filterSlideNumbers, forKey: Keys.filterSlideNumbers) }
    }
    var customFilterPatternsText: String {
        didSet { UserDefaults.standard.set(customFilterPatternsText, forKey: Keys.customFilterPatterns) }
    }

    private enum Keys {
        static let mediaDirectory = "mediaDirectoryPath"
        static let filterStageDirections = "filterStageDirections"
        static let filterSlideNumbers = "filterSlideNumbers"
        static let customFilterPatterns = "customFilterPatterns"
    }

    init() {
        let defaults = UserDefaults.standard
        filterStageDirections = defaults.object(forKey: Keys.filterStageDirections) as? Bool ?? true
        filterSlideNumbers = defaults.object(forKey: Keys.filterSlideNumbers) as? Bool ?? true
        customFilterPatternsText = defaults.string(forKey: Keys.customFilterPatterns) ?? ""

        if let path = defaults.string(forKey: Keys.mediaDirectory) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                // Set the backing store directly — didSet doesn't fire in init,
                // so refresh explicitly below.
                mediaDirectory = URL(fileURLWithPath: path)
            }
        }
        refreshFileLists()
    }

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

    var isRunning: Bool {
        if case .running = alignmentService.state { return true }
        return false
    }

    var canRun: Bool {
        selectedVideo != nil && selectedScript != nil && !isRunning
    }

    var canPreview: Bool {
        selectedScript != nil && !isRunning && !isLoadingPreview
    }

    // MARK: - File selection

    func refreshFileLists() {
        guard let dir = mediaDirectory else {
            availableVideos = []
            availableScripts = []
            return
        }
        availableVideos = Self.scanFiles(in: dir, extensions: Self.videoExtensions)
        availableScripts = Self.scanFiles(in: dir, extensions: Self.scriptExtensions)
        log(.app, "scanned \(dir.lastPathComponent): \(availableVideos.count) videos, \(availableScripts.count) scripts")
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
        if let docx = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docx]
        }
        panel.prompt = "Select Script"

        if panel.runModal() == .OK {
            selectedScript = panel.url
        }
    }

    /// Handle files dropped onto the Generate tab: route by extension.
    /// Returns true if anything was accepted.
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        var accepted = false
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if Self.videoExtensions.contains(ext) {
                selectedVideo = url
                accepted = true
            } else if Self.scriptExtensions.contains(ext) {
                selectedScript = url
                accepted = true
            }
        }
        if accepted {
            log(.app, "files dropped: video=\(selectedVideo?.lastPathComponent ?? "-") script=\(selectedScript?.lastPathComponent ?? "-")")
        }
        return accepted
    }

    private func loadVideoDuration() {
        videoDurationText = nil
        guard let video = selectedVideo else { return }
        Task { [weak self] in
            let asset = AVURLAsset(url: video)
            guard let duration = try? await asset.load(.duration) else { return }
            let seconds = Int(duration.seconds.rounded())
            guard let self, self.selectedVideo == video else { return }
            self.videoDurationText = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    // MARK: - Script preview

    /// Run the fast extract-only pass and show the result in a sheet, so
    /// filter patterns can be sanity-checked without a full alignment run.
    func previewScriptExtraction() async {
        guard let script = selectedScript else { return }
        isLoadingPreview = true
        defer { isLoadingPreview = false }

        let stem = selectedVideo?.deletingPathExtension().lastPathComponent
        do {
            let result = try await alignmentService.extractScriptPreview(
                docxURL: script,
                videoStem: stem,
                filterPatterns: activeFilterPatterns,
                stripPatterns: activeStripPatterns
            )
            previewHeading = result.heading
            previewLines = result.lines
            showScriptPreview = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Alignment

    func runAlignment() async {
        guard let video = selectedVideo, let script = selectedScript else { return }

        errorMessage = nil
        UserNotifier.requestAuthorizationIfNeeded()

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
            do {
                let rawCues = try SRTParser.parse(contentsOf: srtURL)
                let compliant = CaptionComplianceService.makeCompliant(rawCues)
                try SRTParser.serialize(compliant).write(to: srtURL, atomically: true, encoding: .utf8)
                log(.alignment, "compliance pass: \(rawCues.count) -> \(compliant.count) cues")
            } catch {
                logWarn(.alignment, "compliance post-process failed (keeping raw SRT): \(error.localizedDescription)")
            }

            UserNotifier.notifyIfInBackground(
                title: "SRT generation complete",
                body: srtURL.lastPathComponent
            )
        } catch is CancellationError {
            // User pressed Cancel — no error UI.
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            UserNotifier.notifyIfInBackground(
                title: "SRT generation failed",
                body: String(error.localizedDescription.prefix(120))
            )
        }
    }

    func cancelAlignment() {
        alignmentService.cancel()
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
