import AppKit
import Foundation

/// Assembles a plain-text diagnostics report (versions, environment, recent
/// log lines) that a user can paste into an email or bug report.
enum DiagnosticsService {

    /// Build the full report. Runs the Python/pip probes off the main thread.
    static func buildReport() async -> String {
        let env = PythonEnvironmentManager.shared

        var sections: [String] = []
        sections.append(
            """
            === SRT Workbench Diagnostics ===
            Generated:    \(ISO8601DateFormatter().string(from: Date()))
            App version:  \(appVersion())
            macOS:        \(ProcessInfo.processInfo.operatingSystemVersionString)
            Architecture: \(machineArchitecture())
            """
        )

        var environment = "=== Environment ===\n"
        environment += "Python location: \(env.pythonLocationDescription)\n"
        if let python = env.pythonURL {
            environment += "Python path:     \(python.path)\n"
            let version = await runForOutput(python, ["--version"]) ?? "unknown"
            environment += "Python version:  \(version.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        } else {
            environment += "Python:          NOT FOUND\n"
        }
        environment += "Setup sentinel:  \(env.isSetupComplete ? "present" : "MISSING")\n"
        environment += "Model:           \(modelDescription(env))"
        sections.append(environment)

        if let python = env.pythonURL {
            let pip = python.deletingLastPathComponent().appendingPathComponent("pip")
            if let freeze = await runForOutput(pip, ["freeze"]) {
                sections.append("=== Installed packages (pip freeze) ===\n\(freeze.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        sections.append("=== Recent log (\(AppLog.shared.logFileURL.path)) ===\n\(AppLog.shared.recentLines(200))")

        return sections.joined(separator: "\n\n")
    }

    /// Build the report and put it on the general pasteboard.
    static func copyReportToClipboard() async {
        let report = await buildReport()
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
        log(.app, "diagnostics report copied to clipboard (\(report.count) chars)")
    }

    static func openLogFolder() {
        NSWorkspace.shared.open(AppLog.shared.logDirectory)
    }

    // MARK: - Helpers

    static func appVersion() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }

    private static func machineArchitecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
    }

    private static func modelDescription(_ env: PythonEnvironmentManager) -> String {
        guard env.isModelDownloaded else { return "NOT DOWNLOADED" }
        let attributes = (try? FileManager.default.attributesOfItem(atPath: env.modelURL.path)) ?? [:]
        let bytes = (attributes[.size] as? Int) ?? 0
        let mb = Double(bytes) / 1_048_576
        return String(format: "present, %.0f MB", mb)
    }

    /// Run a process and capture combined stdout+stderr, off the main thread.
    private static func runForOutput(_ executable: URL, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = arguments
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}
