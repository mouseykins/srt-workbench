import Foundation

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
    private var continuation: CheckedContinuation<Void, any Error>?

    private static let modelURLString = "https://huggingface.co/deskpai/ctc_forced_aligner/resolve/main/04ac86b67129634da93aea76e0147ef3.onnx"

    func download() async throws {
        let envManager = PythonEnvironmentManager.shared
        let destURL = envManager.modelURL

        // Already downloaded
        if envManager.isModelDownloaded {
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

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            self.continuation = cont
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
            let task = session.downloadTask(with: sourceURL)
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destURL = PythonEnvironmentManager.shared.modelURL
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
            state = .completed
            continuation?.resume()
            continuation = nil
        } catch {
            state = .failed(error.localizedDescription)
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            state = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            state = .failed(error.localizedDescription)
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
