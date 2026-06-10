import AppKit
import Foundation

enum AlignmentStep: String, CaseIterable, Equatable {
    case extractAudio = "Extract audio"
    case loadModel = "Load alignment model"
    case generateEmissions = "Transcribe audio"
    case runAlignment = "Run forced alignment"
    case generateSRT = "Generate SRT file"
}

enum AlignmentState: Equatable {
    case idle
    case running(currentStep: AlignmentStep)
    case complete(srtURL: URL)
    case failed(String)
}

@MainActor
@Observable
class AlignmentService {
    var state: AlignmentState = .idle
    var matchedSection: String?

    /// Overall progress 0–100, driven by the Python runner's percent values.
    var progressPercent: Double = 0
    /// The runner's human-readable stage line ("Transcribing audio…").
    var stageText: String = ""
    /// Run context, e.g. "2,134 words · 14:32 of audio".
    var runInfo: String?
    /// When the current run started — drives the elapsed-time display.
    var startedAt: Date?

    private var process: Process?
    private var isCancelled = false
    /// The most recent {"type": "error"} message from the runner. Preferred
    /// over raw stderr when reporting failure.
    private var pythonReportedError: String?

    struct AlignmentCancelled: Error {}

    /// Run the full alignment pipeline: extract audio → run Python alignment → return SRT
    func runAlignment(videoURL: URL, docxURL: URL, outputDir: URL, filterPatterns: [String] = [], stripPatterns: [String] = []) async throws -> URL {
        state = .running(currentStep: .extractAudio)
        matchedSection = nil
        runInfo = nil
        progressPercent = 0
        stageText = AlignmentStep.extractAudio.rawValue
        startedAt = Date()
        isCancelled = false
        pythonReportedError = nil

        log(.alignment, "=== alignment run started ===")
        log(.alignment, "video:  \(videoURL.path)")
        log(.alignment, "script: \(docxURL.path)")
        log(.alignment, "filters: \(filterPatterns.count), strips: \(stripPatterns.count)")

        defer {
            startedAt = nil
            NSApp.dockTile.badgeLabel = nil
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 1: Extract audio to WAV using AVFoundation
        let wavURL = tempDir.appendingPathComponent("audio.wav")
        let extractStart = Date()
        try await AudioExtractor.extractMonoWAV(from: videoURL, to: wavURL)
        log(.audio, String(format: "audio extracted in %.1fs", Date().timeIntervalSince(extractStart)))

        // Step 2: Run Python alignment (Python parses .docx with python-docx)
        let srtFilename = videoURL.deletingPathExtension().lastPathComponent + " - aligned.srt"
        let srtURL = outputDir.appendingPathComponent(srtFilename)

        let videoStem = videoURL.deletingPathExtension().lastPathComponent

        do {
            try await runPythonAlignment(audioPath: wavURL, docxPath: docxURL, outputPath: srtURL, videoStem: videoStem, filterPatterns: filterPatterns, stripPatterns: stripPatterns)
        } catch is AlignmentCancelled {
            log(.alignment, "alignment cancelled by user")
            state = .idle
            throw CancellationError()
        } catch {
            logError(.alignment, "alignment failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            throw error
        }

        log(.alignment, "=== alignment complete: \(srtURL.lastPathComponent) ===")
        state = .complete(srtURL: srtURL)
        return srtURL
    }

    func cancel() {
        guard case .running = state else { return }
        log(.alignment, "cancel requested")
        isCancelled = true
        process?.terminate()
        // State is reset to .idle by the termination path in runAlignment.
    }

    /// Parse the .docx in extract-only mode and return the lines that would be
    /// aligned — fast (no model imports), used by the script preview sheet.
    func extractScriptPreview(docxURL: URL, videoStem: String?, filterPatterns: [String], stripPatterns: [String]) async throws -> (heading: String?, lines: [String]) {
        var input: [String: Any] = [
            "mode": "extract",
            "docx_path": docxURL.path,
            "filter_patterns": filterPatterns,
            "strip_patterns": stripPatterns,
        ]
        if let videoStem { input["video_stem"] = videoStem }

        log(.alignment, "script preview: \(docxURL.lastPathComponent) (stem: \(videoStem ?? "none"))")
        let messages = try await runRunnerCollectingOutput(input: input)

        for json in messages {
            if json["type"] as? String == "error", let message = json["message"] as? String {
                throw NSError(domain: "AlignmentService", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            if json["type"] as? String == "extract_result" {
                let heading = json["heading"] as? String
                let lines = json["lines"] as? [String] ?? []
                return (heading, lines)
            }
        }
        throw NSError(domain: "AlignmentService", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Script preview produced no result"])
    }

    // MARK: - Python process plumbing

    private func makeRunnerProcess() throws -> Process {
        let envManager = PythonEnvironmentManager.shared

        guard let pythonURL = envManager.pythonURL, envManager.isPythonAvailable else {
            throw PythonEnvError.pythonNotFound
        }
        guard let scriptURL = envManager.alignmentScriptURL else {
            throw PythonEnvError.scriptNotFound
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = [scriptURL.path]
        proc.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        // Clean environment: remove PYTHONHOME/PYTHONPATH that could
        // interfere with the venv's own module resolution.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "PYTHONHOME")
        env.removeValue(forKey: "PYTHONPATH")
        proc.environment = env
        return proc
    }

    /// Run the runner to completion and return every JSON message it printed.
    /// Used for the fast extract mode where streaming progress isn't needed.
    private func runRunnerCollectingOutput(input: [String: Any]) async throws -> [[String: Any]] {
        let proc = try makeRunnerProcess()
        let inputData = try JSONSerialization.data(withJSONObject: input)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            // Read both pipes concurrently while the process runs — reading
            // only after exit would deadlock once output exceeds the 64 KB
            // pipe buffer (easily reached by a long extracted script).
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try proc.run()
                    try stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
                    try stdinPipe.fileHandleForWriting.close()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                var stderrData = Data()
                let stderrDone = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stderrDone.signal()
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                stderrDone.wait()
                proc.waitUntilExit()

                if let stderrText = String(data: stderrData, encoding: .utf8), !stderrText.isEmpty {
                    for line in stderrText.components(separatedBy: "\n") where !line.isEmpty {
                        log(.alignment, "[python] \(line)")
                    }
                }

                let messages = String(data: stdoutData, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .compactMap { line -> [String: Any]? in
                        guard let data = line.data(using: .utf8) else { return nil }
                        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    } ?? []

                if proc.terminationStatus == 0 || !messages.isEmpty {
                    continuation.resume(returning: messages)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AlignmentService", code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Script preview exited with code \(proc.terminationStatus)"]))
                }
            }
        }
    }

    private func runPythonAlignment(audioPath: URL, docxPath: URL, outputPath: URL, videoStem: String, filterPatterns: [String] = [], stripPatterns: [String] = []) async throws {
        let proc = try makeRunnerProcess()

        let input: [String: Any] = [
            "audio_path": audioPath.path,
            "docx_path": docxPath.path,
            "output_path": outputPath.path,
            "model_path": PythonEnvironmentManager.shared.modelURL.path,
            "video_stem": videoStem,
            "filter_patterns": filterPatterns,
            "strip_patterns": stripPatterns,
        ]
        let inputData = try JSONSerialization.data(withJSONObject: input)

        state = .running(currentStep: .loadModel)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc
        defer { self.process = nil }

        let stdoutBuffer = LineBuffer()
        let stderrBuffer = LineBuffer()
        let stderrLines = LineAccumulator()
        let resumeOnce = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // Read stdout for JSON progress lines. Chunks from a pipe can split
            // a line (or even a UTF-8 character), so buffer until newline.
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let lines = stdoutBuffer.appendAndExtractLines(handle.availableData)
                guard !lines.isEmpty else { return }
                Task { @MainActor [weak self] in
                    for line in lines { self?.handleRunnerLine(line) }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let lines = stderrBuffer.appendAndExtractLines(handle.availableData)
                for line in lines {
                    stderrLines.append(line)
                    log(.alignment, "[python] \(line)")
                }
            }

            proc.terminationHandler = { proc in
                // Drain anything still in the pipes so a final JSON error
                // line can't be lost to the handler/termination race.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                var remainingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()).flatMap {
                    stdoutBuffer.appendAndExtractLines($0)
                } ?? []
                remainingStdout.append(contentsOf: stdoutBuffer.flushRemainder())

                let remainingStderr = ((try? stderrPipe.fileHandleForReading.readToEnd()).flatMap {
                    stderrBuffer.appendAndExtractLines($0)
                } ?? []) + stderrBuffer.flushRemainder()
                for line in remainingStderr {
                    stderrLines.append(line)
                    log(.alignment, "[python] \(line)")
                }

                let status = proc.terminationStatus
                Task { @MainActor [weak self] in
                    for line in remainingStdout { self?.handleRunnerLine(line) }

                    guard resumeOnce.attempt() else { return }
                    log(.alignment, "runner exited with status \(status)")

                    if self?.isCancelled == true {
                        continuation.resume(throwing: AlignmentCancelled())
                    } else if status == 0 {
                        continuation.resume()
                    } else {
                        // Prefer the runner's structured error message; fall
                        // back to stderr, then to a generic exit-code message.
                        let stderrText = stderrLines.joined()
                        let msg = self?.pythonReportedError
                            ?? (stderrText.isEmpty ? "Alignment process exited with code \(status)" : stderrText)
                        continuation.resume(throwing: NSError(
                            domain: "AlignmentService", code: Int(status),
                            userInfo: [NSLocalizedDescriptionKey: msg]))
                    }
                }
            }

            do {
                try proc.run()
                // Send input JSON on stdin. write(contentsOf:) throws on a
                // broken pipe instead of raising an uncatchable exception.
                try stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                if resumeOnce.attempt() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Runner message handling (main actor)

    private func handleRunnerLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "progress":
            let percent = json["percent"] as? Double ?? 0
            let stage = json["stage"] as? String ?? ""
            applyProgress(percent: percent, stage: stage)
        case "info":
            let words = json["words"] as? Int ?? 0
            let audioSeconds = json["audio_seconds"] as? Double ?? 0
            runInfo = Self.formatRunInfo(words: words, audioSeconds: audioSeconds)
        case "section_match":
            let matched = json["matched"] as? Bool ?? false
            if matched, let heading = json["heading"] as? String {
                matchedSection = heading
            } else {
                matchedSection = nil
            }
        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            pythonReportedError = message
        default:
            break
        }
    }

    private func applyProgress(percent: Double, stage: String) {
        progressPercent = percent
        if !stage.isEmpty { stageText = stage }

        let step: AlignmentStep
        if percent <= 10 {
            step = .loadModel
        } else if percent < 50 {
            step = .generateEmissions
        } else if percent <= 80 {
            step = .runAlignment
        } else {
            step = .generateSRT
        }
        state = .running(currentStep: step)

        NSApp.dockTile.badgeLabel = "\(Int(percent))%"
    }

    private static func formatRunInfo(words: Int, audioSeconds: Double) -> String {
        let wordsText = NumberFormatter.localizedString(from: NSNumber(value: words), number: .decimal)
        let minutes = Int(audioSeconds) / 60
        let seconds = Int(audioSeconds) % 60
        return "\(wordsText) words · \(minutes):\(String(format: "%02d", seconds)) of audio"
    }
}

// MARK: - Thread-safe helpers (touched from pipe-reader threads)

/// Accumulates raw pipe data and yields complete newline-terminated lines.
/// Buffering by byte means a UTF-8 character split across chunks is reassembled.
private final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func appendAndExtractLines(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }
        return lines
    }

    /// Return any unterminated final line and clear the buffer.
    func flushRemainder() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8) else {
            buffer = Data()
            return []
        }
        buffer = Data()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }
}

/// Thread-safe ordered line collection (for stderr capture).
private final class LineAccumulator: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

/// Guarantees a checked continuation is resumed exactly once across the
/// stdin-write failure path and the termination handler.
private final class ResumeOnce: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    func attempt() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
