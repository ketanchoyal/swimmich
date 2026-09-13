import AVFoundation
import CoreGraphics
import Foundation

/// Builds throwaway media files for tests — a genuine H.264 movie, written by
/// `AVAssetWriter` rather than pasted, so decoding it is a real exercise of the
/// poster-frame and playback paths.
enum VideoFixture {

    /// A one-second 64×64 movie. Small, but a real MP4: `AVAssetImageGenerator`
    /// and `AVPlayer` behave exactly as they would on a server original.
    static func makeMovieData(frameCount: Int = 15, size: Int = 64) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-fixture-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size,
                AVVideoHeightKey: size
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size
            ]
        )
        guard writer.canAdd(input) else { throw VideoFixtureError.writerRejectedInput }
        writer.add(input)
        guard writer.startWriting() else { throw VideoFixtureError.startFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let buffer = try makePixelBuffer(size: size, frame: frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: 15)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw VideoFixtureError.appendFailed(writer.error)
            }
        }
        input.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 20)
        guard writer.status == .completed else { throw VideoFixtureError.finishFailed(writer.error) }

        return try Data(contentsOf: url)
    }

    private static func makePixelBuffer(size: Int, frame: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw VideoFixtureError.pixelBufferFailed(status)
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            // A per-frame colour, so the poster frame is identifiable.
            let shade = UInt8(60 + (frame * 12) % 180)
            for row in 0..<size {
                let rowStart = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for column in 0..<size {
                    let pixel = rowStart.advanced(by: column * 4)
                    pixel[0] = shade      // B
                    pixel[1] = 0x50       // G
                    pixel[2] = 0xAF       // R
                    pixel[3] = 0xFF       // A
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}

enum VideoFixtureError: Error {
    case writerRejectedInput
    case startFailed(Error?)
    case appendFailed(Error?)
    case finishFailed(Error?)
    case pixelBufferFailed(CVReturn)
}
