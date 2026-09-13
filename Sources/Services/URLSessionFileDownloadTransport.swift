import Foundation

/// `URLSession`-backed `FileDownloadTransport`.
///
/// `URLSession.download(for:delegate:)` streams the body straight into a
/// system-managed temp file — the bytes never pass through this process as a
/// `Data`, which is what makes caching a multi-gigabyte video survivable.
struct URLSessionFileDownloadTransport: FileDownloadTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(
        _ request: URLRequest,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> DownloadedFile {
        let delegate = ProgressDelegate(onProgress: onProgress)
        let (fileURL, response) = try await session.download(for: request, delegate: delegate)
        let http = response as? HTTPURLResponse
        return DownloadedFile(
            url: fileURL,
            statusCode: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type")
        )
    }
}

/// Bridges `URLSessionDownloadDelegate`'s byte callbacks to a plain closure.
/// URLSession calls it on its own queue, hence `@unchecked Sendable`: the
/// closure is `@Sendable` and the class holds no mutable state.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }
}
