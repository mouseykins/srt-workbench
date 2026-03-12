import Foundation

/// Manages the complete first-launch setup: Python environment + ONNX model.
/// Runs automatically — no shell scripts needed.
@Observable
class SetupManager {
    static let shared = SetupManager()

    enum Stage: Equatable {
        case checking
        case findingPython
        case creatingVenv(progress: String)
        case installingDependencies(progress: String)
        case downloadingModel(progress: Double)
        case ready
        case failed(String)
    }

    var stage: Stage = .checking

    /// Whether the full environment (Python + model) is ready
    var isReady: Bool {
        PythonEnvironmentManager.shared.isPythonAvailable &&
        PythonEnvironmentManager.shared.isModelDownloaded
    }

    private let envManager = PythonEnvironmentManager.shared
    private var modelDownloader = ModelDownloader()

    /// Run the full setup. Skips steps that are already done.
    func runSetup() async {
        stage = .checking

        // Step 1: Python environment
        if !envManager.isPythonAvailable {
            do {
                try await setupPythonEnvironment()
            } catch {
                stage = .failed("Python setup failed: \(error.localizedDescription)")
                return
            }
        }

        // Step 2: ONNX model
        if !envManager.isModelDownloaded {
            do {
                try await downloadModel()
            } catch {
                stage = .failed("Model download failed: \(error.localizedDescription)")
                return
            }
        }

        stage = .ready
    }

    // MARK: - Python Environment Setup

    private func setupPythonEnvironment() async throws {
        stage = .findingPython

        // Find a system Python 3.10+
        guard let systemPython = findSystemPython() else {
            throw SetupError.noPythonFound
        }

        let venvPath = envManager.appSupportURL.appendingPathComponent("python")

        // Create venv
        stage = .creatingVenv(progress: "Creating virtual environment...")
        try await runProcess(
            executable: URL(fileURLWithPath: systemPython),
            arguments: ["-m", "venv", venvPath.path]
        )

        // Upgrade pip
        stage = .installingDependencies(progress: "Upgrading pip...")
        let pipPath = venvPath.appendingPathComponent("bin/pip").path
        try await runProcess(
            executable: URL(fileURLWithPath: pipPath),
            arguments: ["install", "--upgrade", "pip", "--quiet"]
        )

        // Install alignment dependencies
        stage = .installingDependencies(progress: "Installing alignment libraries (this may take a few minutes)...")
        try await runProcess(
            executable: URL(fileURLWithPath: pipPath),
            arguments: ["install", "ctc-forced-aligner", "Unidecode", "python-docx", "--no-cache-dir"]
        )

        // Verify
        stage = .installingDependencies(progress: "Verifying installation...")
        let pythonPath = venvPath.appendingPathComponent("bin/python3").path
        try await runProcess(
            executable: URL(fileURLWithPath: pythonPath),
            arguments: ["-c", "from ctc_forced_aligner import AlignmentSingleton; print('OK')"]
        )
    }

    /// Search for a usable Python 3.10+ on the system
    private func findSystemPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3.10",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.13",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }

            // Check version is 3.10+
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["--version"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // Parse "Python 3.X.Y"
            if let match = output.range(of: #"3\.(\d+)"#, options: .regularExpression) {
                let minorStr = String(output[match]).components(separatedBy: ".").last ?? "0"
                if let minor = Int(minorStr), minor >= 10 {
                    return path
                }
            }
        }
        return nil
    }

    // MARK: - Model Download

    private func downloadModel() async throws {
        stage = .downloadingModel(progress: 0)

        // Observe model downloader state changes
        let task = Task { @MainActor in
            // Poll the downloader state to update our stage
            while !Task.isCancelled {
                switch modelDownloader.state {
                case .downloading(let progress):
                    stage = .downloadingModel(progress: progress)
                case .completed:
                    return
                case .failed(let msg):
                    stage = .failed("Model download failed: \(msg)")
                    return
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        try await modelDownloader.download()
        task.cancel()
    }

    // MARK: - Process Helper

    private func runProcess(executable: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let proc = Process()
            proc.executableURL = executable
            proc.arguments = arguments

            // Clean environment — don't leak PYTHONHOME etc.
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "PYTHONHOME")
            env.removeValue(forKey: "PYTHONPATH")
            proc.environment = env

            let stderrPipe = Pipe()
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = stderrPipe

            proc.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let msg = stderr.isEmpty ? "Process exited with code \(proc.terminationStatus)" : stderr
                    continuation.resume(throwing: SetupError.processFailed(msg))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum SetupError: LocalizedError {
    case noPythonFound
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPythonFound:
            return "Python 3.10+ not found on this Mac.\n\nInstall it with:\n  brew install python@3.10\n\nThen relaunch the app."
        case .processFailed(let msg):
            return msg
        }
    }
}
