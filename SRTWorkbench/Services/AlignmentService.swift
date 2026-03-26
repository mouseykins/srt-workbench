import Foundation

enum AlignmentStep: String, CaseIterable, Equatable {
    case extractAudio = "Extract audio"
    case loadModel = "Load alignment model"
    case generateEmissions = "Process audio emissions"
    case runAlignment = "Run forced alignment"
    case generateSRT = "Generate SRT file"
}

enum AlignmentState: Equatable {
    case idle
    case running(currentStep: AlignmentStep)
    case complete(srtURL: URL)
    case failed(String)
}

@Observable
class AlignmentService {
    var state: AlignmentState = .idle
    var matchedSection: String?

    private var process: Process?

    /// Run the full alignment pipeline: extract audio → run Python alignment → return SRT
    func runAlignment(videoURL: URL, docxURL: URL, outputDir: URL, filterPatterns: [String] = [], stripPatterns: [String] = []) async throws -> URL {
        state = .running(currentStep: .extractAudio)
        matchedSection = nil

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 1: Extract audio to WAV using AVFoundation
        let wavURL = tempDir.appendingPathComponent("audio.wav")
        try await AudioExtractor.extractMonoWAV(from: videoURL, to: wavURL)

        // Step 2: Run Python alignment (Python parses .docx with python-docx)
        let srtFilename = videoURL.deletingPathExtension().lastPathComponent + " - aligned.srt"
        let srtURL = outputDir.appendingPathComponent(srtFilename)

        let videoStem = videoURL.deletingPathExtension().lastPathComponent
        try await runPythonAlignment(audioPath: wavURL, docxPath: docxURL, outputPath: srtURL, videoStem: videoStem, filterPatterns: filterPatterns, stripPatterns: stripPatterns)

        state = .complete(srtURL: srtURL)
        return srtURL
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
    }

    // MARK: - Private

    private func runPythonAlignment(audioPath: URL, docxPath: URL, outputPath: URL, videoStem: String, filterPatterns: [String] = [], stripPatterns: [String] = []) async throws {
        let envManager = PythonEnvironmentManager.shared

        guard let pythonURL = envManager.pythonURL, envManager.isPythonAvailable else {
            throw PythonEnvError.pythonNotFound
        }
        guard let scriptURL = envManager.alignmentScriptURL else {
            throw PythonEnvError.scriptNotFound
        }

        let input: [String: Any] = [
            "audio_path": audioPath.path,
            "docx_path": docxPath.path,
            "output_path": outputPath.path,
            "model_path": envManager.modelURL.path,
            "video_stem": videoStem,
            "filter_patterns": filterPatterns,
            "strip_patterns": stripPatterns,
        ]

        let inputData = try JSONSerialization.data(withJSONObject: input)

        state = .running(currentStep: .loadModel)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardInput = stdinPipe
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            self.process = proc

            // Read stdout for JSON progress lines
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                // Parse JSON progress lines
                for jsonLine in line.components(separatedBy: "\n") where !jsonLine.isEmpty {
                    self?.parseProgressLine(jsonLine)
                }
            }

            let stderrAccumulator = StderrAccumulator()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8) {
                    stderrAccumulator.append(str)
                }
            }

            proc.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stderrOutput = stderrAccumulator.value
                DispatchQueue.main.async { [weak self] in
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let msg = stderrOutput.isEmpty ? "Alignment process exited with code \(proc.terminationStatus)" : stderrOutput
                        self?.state = .failed(msg)
                        continuation.resume(throwing: NSError(domain: "AlignmentService", code: Int(proc.terminationStatus),
                                                              userInfo: [NSLocalizedDescriptionKey: msg]))
                    }
                }
            }

            do {
                try proc.run()
                // Send input JSON on stdin
                stdinPipe.fileHandleForWriting.write(inputData)
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseProgressLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            switch type {
            case "progress":
                let percent = json["percent"] as? Double ?? 0
                let step: AlignmentStep
                if percent <= 10 {
                    step = .loadModel
                } else if percent <= 50 {
                    step = .generateEmissions
                } else if percent <= 80 {
                    step = .runAlignment
                } else {
                    step = .generateSRT
                }
                self?.state = .running(currentStep: step)
            case "section_match":
                let matched = json["matched"] as? Bool ?? false
                if matched, let heading = json["heading"] as? String {
                    self?.matchedSection = heading
                } else {
                    self?.matchedSection = nil
                }
            case "error":
                let message = json["message"] as? String ?? "Unknown error"
                self?.state = .failed(message)
            default:
                break
            }
        }
    }
}

/// Thread-safe accumulator for stderr output
private final class StderrAccumulator: @unchecked Sendable {
    private var _value = ""
    private let lock = NSLock()

    func append(_ str: String) {
        lock.lock()
        _value += str
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
