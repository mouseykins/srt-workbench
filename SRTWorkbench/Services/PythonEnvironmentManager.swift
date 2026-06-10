import Foundation

enum PythonEnvError: LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python environment not found. Relaunch the app to trigger automatic setup."
        case .scriptNotFound:
            return "Alignment runner script not found in app resources"
        case .modelNotFound:
            return "ONNX model not found. Please download it first."
        }
    }
}

@Observable
class PythonEnvironmentManager {
    static let shared = PythonEnvironmentManager()

    /// Application Support directory for app data (Python env, model, etc.)
    var appSupportURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SRT Workbench")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Resolves the Python binary by searching multiple locations in order:
    /// 1. ~/Library/Application Support/SRT Workbench/python/bin/python3
    /// 2. Inside the .app bundle Resources/python/bin/python3
    var pythonURL: URL? {
        let candidates = [
            // App Support (created by build_python_env.sh)
            appSupportURL.appendingPathComponent("python/bin/python3"),
            // Bundled in .app (for fully self-contained distribution)
            Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3"),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Path to the alignment runner script (bundled in app resources)
    var alignmentScriptURL: URL? {
        Bundle.main.url(forResource: "alignment_runner", withExtension: "py")
    }

    /// Path where the ONNX model is stored
    var modelURL: URL {
        appSupportURL.appendingPathComponent("models/model.onnx")
    }

    /// Check if the ONNX model has been downloaded
    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// Check if a Python environment is available (any location)
    var isPythonAvailable: Bool {
        pythonURL != nil
    }

    /// Sentinel file written only after dependencies were installed AND
    /// verified. An interrupted first-run setup (user quit mid-pip-install)
    /// leaves a venv whose python3 binary exists but whose packages are
    /// broken — the sentinel's absence detects exactly that.
    var setupSentinelURL: URL {
        appSupportURL.appendingPathComponent("python/.setup-complete")
    }

    /// True when the Python environment finished a verified setup.
    var isSetupComplete: Bool {
        guard let url = pythonURL else { return false }
        // A Python bundled inside the .app ships pre-installed — no sentinel.
        if url.path.contains(".app/") { return true }
        return FileManager.default.fileExists(atPath: setupSentinelURL.path)
    }

    /// Human-readable description of where Python was found
    var pythonLocationDescription: String {
        guard let url = pythonURL else { return "Not found" }
        if url.path.contains("Application Support") {
            return "Application Support"
        } else if url.path.contains(".app/") {
            return "App Bundle"
        }
        return url.deletingLastPathComponent().deletingLastPathComponent().path
    }

    /// Validate the full environment is ready
    func validate() throws {
        guard isPythonAvailable else { throw PythonEnvError.pythonNotFound }
        guard alignmentScriptURL != nil else { throw PythonEnvError.scriptNotFound }
        guard isModelDownloaded else { throw PythonEnvError.modelNotFound }
    }
}
