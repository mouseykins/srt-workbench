import AVFoundation
import Foundation

enum AudioExtractorError: LocalizedError {
    case noAudioTrack
    case readerSetupFailed(String)
    case extractionFailed(String)
    case wavWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "No audio track found in video"
        case .readerSetupFailed(let msg): return "Audio reader setup failed: \(msg)"
        case .extractionFailed(let msg): return "Audio extraction failed: \(msg)"
        case .wavWriteFailed(let msg): return "WAV file write failed: \(msg)"
        }
    }
}

enum AudioExtractor {
    /// Extract audio from a video file as mono 16kHz 16-bit PCM WAV.
    /// This replaces the ffmpeg dependency from the web app.
    static func extractMonoWAV(from videoURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioExtractorError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioExtractorError.readerSetupFailed(error.localizedDescription)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(readerOutput) else {
            throw AudioExtractorError.readerSetupFailed("Cannot add audio output to reader")
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw AudioExtractorError.extractionFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        // Collect all PCM sample buffers
        var pcmData = Data()
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            pcmData.append(data)
        }

        if reader.status == .failed {
            throw AudioExtractorError.extractionFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        // Write WAV file with proper header
        try writeWAV(pcmData: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16, to: outputURL)
    }

    private static func writeWAV(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int, to url: URL) throws {
        var data = Data()

        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))       // chunk size
        data.append(littleEndian: UInt16(1))        // PCM format
        data.append(littleEndian: UInt16(channels))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(byteRate))
        data.append(littleEndian: UInt16(blockAlign))
        data.append(littleEndian: UInt16(bitsPerSample))

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)
        data.append(pcmData)

        try data.write(to: url)
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
