import Foundation

/// A body streamed to disk by a `FileDownloadTransport`.
///
/// The HTTP metadata travels alongside the file so the caller — not the
/// transport — owns the policy: whether a status is fatal, and how the
/// Content-Type maps to a file extension.
struct DownloadedFile: Sendable {
    let url: URL
    let statusCode: Int?
    let contentType: String?
}

/// Streams an HTTP response body to a file on disk.
///
/// The offline cache downloads **originals** (photos and videos): the body can
/// be hundreds of megabytes, so it must never be materialized as `Data` in
/// memory. A transport returns a temporary file the caller owns — it moves or
/// deletes it.
///
/// The seam exists for a second reason: progress. A test double can report
/// determinate progress, which a `URLProtocol` stub cannot (custom protocols
/// deliver the payload in one shot and never call the download delegate).
protocol FileDownloadTransport: Sendable {
    /// Downloads the URL of `request`.
    ///
    /// - Parameter onProgress: `(received, expected)`. `expected` is `0` when
    ///   the server sends no `Content-Length`, and the caller then shows an
    ///   indeterminate bar rather than a frozen 0 %.
    func download(
        _ request: URLRequest,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> DownloadedFile
}
