import Foundation

/// Manages the complete first-launch setup: Python environment + ONNX model.
/// Runs automatically — no shell scripts needed.
@MainActor
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

    /// Whether the full environment (verified Python setup + model) is ready
    var isReady: Bool {
        PythonEnvironmentManager.shared.isSetupComplete &&
        PythonEnvironmentManager.shared.isModelDownloaded
    }

    private let envManager = PythonEnvironmentManager.shared
    private var modelDownloader = ModelDownloader()

    /// Run the full setup. Skips steps that are already done.
    func runSetup() async {
        stage = .checking
        log(.setup, "setup check: pythonAvailable=\(envManager.isPythonAvailable) setupComplete=\(envManager.isSetupComplete) modelDownloaded=\(envManager.isModelDownloaded)")

        // Step 1: Python environment (sentinel-verified, not just binary-present)
        if !envManager.isSetupComplete {
            do {
                try await setupPythonEnvironment()
            } catch SetupError.noPythonFound {
                stage = .failed(SetupError.noPythonFound.localizedDescription)
                return
            } catch {
                // An interrupted or half-broken previous attempt can leave a
                // poisoned venv. Throw it away and try once from scratch.
                logWarn(.setup, "setup failed (\(error.localizedDescription)) — retrying with a fresh environment")
                try? FileManager.default.removeItem(at: venvPath)
                do {
                    try await setupPythonEnvironment()
                } catch {
                    logError(.setup, "setup failed after retry: \(error.localizedDescription)")
                    stage = .failed("Python setup failed: \(Self.condense(error.localizedDescription))")
                    return
                }
            }
        }

        // Step 2: ONNX model
        if !envManager.isModelDownloaded {
            do {
                try await downloadModel()
            } catch {
                logError(.download, "model download failed: \(error.localizedDescription)")
                stage = .failed("Model download failed: \(Self.condense(error.localizedDescription))")
                return
            }
        }

        log(.setup, "setup complete")
        stage = .ready
    }

    // MARK: - Python Environment Setup

    private var venvPath: URL {
        envManager.appSupportURL.appendingPathComponent("python")
    }

    private func setupPythonEnvironment() async throws {
        // Fast path: an existing environment that verifies cleanly only needs
        // its sentinel stamped (covers upgrades from v1.x, which had none) —
        // no multi-minute pip reinstall.
        if let existingPython = envManager.pythonURL {
            stage = .installingDependencies(progress: "Verifying existing installation...")
            let verified = (try? await runProcess(
                executable: existingPython,
                arguments: ["-c", "from ctc_forced_aligner import AlignmentSingleton; print('OK')"],
                logPrefix: "verify"
            )) != nil
            if verified {
                await writeSentinel()
                log(.setup, "existing python environment verified — skipping reinstall")
                return
            }
            logWarn(.setup, "existing environment failed verification — rebuilding")
        }

        stage = .findingPython

        // Find a system Python 3.10+ (probes block on subprocesses — keep off main)
        guard let systemPython = await Task.detached(operation: { Self.findSystemPython() }).value else {
            logError(.setup, "no Python 3.10+ found on this system")
            throw SetupError.noPythonFound
        }
        log(.setup, "using system python: \(systemPython)")

        // Create venv
        stage = .creatingVenv(progress: "Creating virtual environment...")
        try await runProcess(
            executable: URL(fileURLWithPath: systemPython),
            arguments: ["-m", "venv", venvPath.path],
            logPrefix: "venv"
        )

        // Upgrade pip
        stage = .installingDependencies(progress: "Upgrading pip...")
        let pipPath = venvPath.appendingPathComponent("bin/pip").path
        try await runProcess(
            executable: URL(fileURLWithPath: pipPath),
            arguments: ["install", "--upgrade", "pip", "--quiet"],
            logPrefix: "pip"
        )

        // Install alignment dependencies
        stage = .installingDependencies(progress: "Installing alignment libraries (this may take a few minutes)...")
        try await runProcess(
            executable: URL(fileURLWithPath: pipPath),
            arguments: ["install", "ctc-forced-aligner", "Unidecode", "python-docx", "--no-cache-dir"],
            logPrefix: "pip"
        )

        // Verify
        stage = .installingDependencies(progress: "Verifying installation...")
        let pythonPath = venvPath.appendingPathComponent("bin/python3").path
        try await runProcess(
            executable: URL(fileURLWithPath: pythonPath),
            arguments: ["-c", "from ctc_forced_aligner import AlignmentSingleton; print('OK')"],
            logPrefix: "verify"
        )

        // Record success: sentinel contains the verified package set, which
        // also shows up in diagnostics reports.
        await writeSentinel()
        log(.setup, "python environment verified; sentinel written")
    }

    /// Stamp the environment as complete. Stores `pip freeze` output so the
    /// sentinel doubles as a record of the verified package set.
    private func writeSentinel() async {
        guard let python = envManager.pythonURL else { return }
        let pip = python.deletingLastPathComponent().appendingPathComponent("pip")
        let freeze = (try? await runProcess(
            executable: pip,
            arguments: ["freeze"],
            logPrefix: "freeze",
            logOutput: false
        )) ?? "verified"
        try? freeze.write(to: envManager.setupSentinelURL, atomically: true, encoding: .utf8)
    }

    /// Search for a usable Python 3.10+ on the system
    private nonisolated static func findSystemPython() -> String? {
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
                    log(.setup, "python candidate \(path): \(output.trimmingCharacters(in: .whitespacesAndNewlines)) — accepted")
                    return path
                }
                log(.setup, "python candidate \(path): \(output.trimmingCharacters(in: .whitespacesAndNewlines)) — too old")
            }
        }
        return nil
    }

    // MARK: - Model Download

    private func downloadModel() async throws {
        stage = .downloadingModel(progress: 0)
        try await modelDownloader.download { [weak self] progress in
            self?.stage = .downloadingModel(progress: progress)
        }
    }

    // MARK: - Process Helper

    /// Run a process off the main thread, capturing combined stdout+stderr
    /// into the app log. Returns the output; throws on non-zero exit.
    @discardableResult
    private func runProcess(executable: URL, arguments: [String], logPrefix: String, logOutput: Bool = true) async throws -> String {
        log(.setup, "run: \(executable.lastPathComponent) \(arguments.joined(separator: " "))")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = arguments

                // Clean environment — don't leak PYTHONHOME etc.
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "PYTHONHOME")
                env.removeValue(forKey: "PYTHONPATH")
                proc.environment = env

                // One combined pipe: no cross-pipe deadlock, and the log shows
                // output in the order a terminal would.
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe

                do {
                    try proc.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                if logOutput {
                    for line in output.components(separatedBy: "\n") where !line.isEmpty {
                        log(.setup, "[\(logPrefix)] \(line)")
                    }
                }

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let msg = output.isEmpty
                        ? "Process exited with code \(proc.terminationStatus)"
                        : output
                    continuation.resume(throwing: SetupError.processFailed(msg))
                }
            }
        }
    }

    /// Keep error messages displayable: last few lines only (the full output
    /// is always in the log file).
    private static func condense(_ message: String) -> String {
        let lines = message.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 6 else { return message }
        return (["…"] + lines.suffix(6)).joined(separator: "\n")
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
