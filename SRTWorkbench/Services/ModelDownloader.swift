import Foundation

/// Downloads the ~1.2 GB ONNX alignment model. Supports resuming an
/// interrupted download (the user can hit Retry without restarting from 0%)
/// and sanity-checks the result so an HTML rate-limit page saved as
/// "model.onnx" can't masquerade as a model.
@Observable
class ModelDownloader: NSObject {
    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case completed
        case failed(String)
    }

    var state: State = .idle

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var progressHandler: (@MainActor (Double) -> Void)?
    private var lastReportedPermille = -1

    /// Resume data kept from a failed attempt so Retry continues the download.
    private var resumeData: Data?

    private static let modelURLString = "https://huggingface.co/deskpai/ctc_forced_aligner/resolve/main/04ac86b67129634da93aea76e0147ef3.onnx"

    /// Anything smaller than this is not the model (it's ~1.2 GB) — most
    /// likely an error page served instead of the file.
    private static let minimumPlausibleBytes = 100_000_000

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        let envManager = PythonEnvironmentManager.shared
        let destURL = envManager.modelURL

        // Already downloaded
        if envManager.isModelDownloaded {
            log(.download, "model already present at \(destURL.path)")
            state = .completed
            return
        }

        // Create models directory
        let modelsDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        guard let sourceURL = URL(string: Self.modelURLString) else {
            throw NSError(domain: "ModelDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model URL"])
        }

        state = .downloading(progress: 0)
        progressHandler = progress
        lastReportedPermille = -1

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            self.continuation = cont
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
            self.session = session

            let task: URLSessionDownloadTask
            if let resumeData {
                log(.download, "resuming model download (\(resumeData.count) bytes of resume data)")
                task = session.downloadTask(withResumeData: resumeData)
                self.resumeData = nil
            } else {
                log(.download, "starting model download from \(Self.modelURLString)")
                task = session.downloadTask(with: sourceURL)
            }
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel { [weak self] data in
            self?.resumeData = data
        }
        downloadTask = nil
        state = .idle
    }

    // MARK: - Private

    private func finish(error: (any Error)?) {
        session?.finishTasksAndInvalidate()
        session = nil
        downloadTask = nil
        progressHandler = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destURL = PythonEnvironmentManager.shared.modelURL

        // Plausibility check before accepting the file as a model.
        let attributes = (try? FileManager.default.attributesOfItem(atPath: location.path)) ?? [:]
        let bytes = (attributes[.size] as? Int) ?? 0
        guard bytes >= Self.minimumPlausibleBytes else {
            try? FileManager.default.removeItem(at: location)
            let mb = Double(bytes) / 1_048_576
            let msg = String(format: "Downloaded file is only %.1f MB (expected ~1.2 GB). The server may have rate-limited the download — try again in a few minutes.", mb)
            logError(.download, msg)
            state = .failed(msg)
            finish(error: NSError(domain: "ModelDownloader", code: 2, userInfo: [NSLocalizedDescriptionKey: msg]))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
            log(.download, String(format: "model downloaded: %.0f MB -> %@", Double(bytes) / 1_048_576, destURL.path))
            state = .completed
            finish(error: nil)
        } catch {
            logError(.download, "failed to move model into place: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            finish(error: error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        state = .downloading(progress: progress)

        // Throttle UI callbacks to 0.1% steps (this delegate fires constantly).
        let permille = Int(progress * 1000)
        if permille != lastReportedPermille, let handler = progressHandler {
            lastReportedPermille = permille
            Task { @MainActor in handler(progress) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }

        // Keep resume data so a Retry continues where this attempt stopped.
        if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeData = data
            log(.download, "kept \(data.count) bytes of resume data for retry")
        }
        logError(.download, "download failed: \(error.localizedDescription)")
        state = .failed(error.localizedDescription)
        finish(error: error)
    }
}
