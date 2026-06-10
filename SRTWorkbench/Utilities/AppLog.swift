import Foundation
import os

/// App-wide logging with two sinks:
///  - Apple unified logging (`os.Logger`), visible in Console.app and via
///    `log show --predicate 'subsystem == "com.srtworkbench.app"'`
///  - A rotating plain-text file in `~/Library/Logs/SRT Workbench/` that a
///    non-technical user can locate and email when something goes wrong.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    enum Category: String, CaseIterable {
        case app, setup, download, alignment, audio, review
    }

    static let subsystem = "com.srtworkbench.app"

    let logDirectory: URL
    let logFileURL: URL

    private let loggers: [Category: Logger]
    private let queue = DispatchQueue(label: "com.srtworkbench.app.logfile", qos: .utility)
    private let maxFileBytes = 1_000_000
    private let maxRotatedFiles = 5

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        loggers = Dictionary(uniqueKeysWithValues: Category.allCases.map {
            ($0, Logger(subsystem: Self.subsystem, category: $0.rawValue))
        })

        let logs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/SRT Workbench")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logDirectory = logs
        logFileURL = logs.appendingPathComponent("SRT Workbench.log")
    }

    // MARK: - Public API

    func info(_ category: Category, _ message: String) {
        loggers[category]?.info("\(message, privacy: .public)")
        appendToFile(level: "INFO ", category: category, message: message)
    }

    func warn(_ category: Category, _ message: String) {
        loggers[category]?.warning("\(message, privacy: .public)")
        appendToFile(level: "WARN ", category: category, message: message)
    }

    func error(_ category: Category, _ message: String) {
        loggers[category]?.error("\(message, privacy: .public)")
        appendToFile(level: "ERROR", category: category, message: message)
    }

    /// Last `count` lines of the current log file (plus the previous rotation
    /// if the current file is short), newest last. Used for diagnostics reports.
    func recentLines(_ count: Int) -> String {
        queue.sync {
            var lines: [String] = []
            for url in [rotatedURL(1), logFileURL] {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    lines.append(contentsOf: text.components(separatedBy: "\n"))
                }
            }
            lines = lines.filter { !$0.isEmpty }
            return lines.suffix(count).joined(separator: "\n")
        }
    }

    // MARK: - File sink

    private func appendToFile(level: String, category: Category, message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let line = "\(timestamp) [\(level)] [\(category.rawValue)] \(message)\n"
        queue.async { [self] in
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    private func rotatedURL(_ index: Int) -> URL {
        logDirectory.appendingPathComponent("SRT Workbench.\(index).log")
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        let attributes = (try? fm.attributesOfItem(atPath: logFileURL.path)) ?? [:]
        let bytes = (attributes[.size] as? Int) ?? 0
        guard bytes >= maxFileBytes else { return }

        try? fm.removeItem(at: rotatedURL(maxRotatedFiles))
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let from = rotatedURL(i)
            if fm.fileExists(atPath: from.path) {
                try? fm.moveItem(at: from, to: rotatedURL(i + 1))
            }
        }
        try? fm.moveItem(at: logFileURL, to: rotatedURL(1))
    }
}

/// Convenience free function so call sites stay short: `log(.alignment, "...")`
func log(_ category: AppLog.Category, _ message: String) {
    AppLog.shared.info(category, message)
}

func logWarn(_ category: AppLog.Category, _ message: String) {
    AppLog.shared.warn(category, message)
}

func logError(_ category: AppLog.Category, _ message: String) {
    AppLog.shared.error(category, message)
}
