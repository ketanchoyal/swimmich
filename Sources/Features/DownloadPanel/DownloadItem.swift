import Foundation

/// Lifecycle of one row of the download queue.
///
/// Mirrors the useful subset of the Flutter client's `TaskStatus`
/// (`mobile/lib/models/download/download_state.model.dart`): `paused` and
/// `notFound` only make sense with `background_downloader` and have no iOS
/// counterpart here.
enum DownloadStatus: String, Sendable, Equatable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

/// One row of the download queue.
///
/// Keyed by asset id: asking twice for the same original raises the same row
/// instead of queueing a second copy — the rule the offline cache follows too
/// (`OfflineAssetStore` is keyed by asset id for the same reason).
struct DownloadItem: Identifiable, Sendable, Equatable {
    /// The row's key. An asset id for a single original; the archive's own
    /// name for a chunk the server returned from `POST /download/info`, since
    /// the server hands back one file per archive and no single asset id
    /// identifies it.
    let id: String
    /// The asset this row carries — equal to `id` for a single original.
    let assetId: String
    /// The server's own file name (`AssetResponseDto.originalFileName`): what
    /// the file is called on disk and in the panel, never the asset id the
    /// offline cache uses.
    let fileName: String
    /// True when this row is a ZIP the server made out of several assets.
    let isArchive: Bool
    /// Bytes announced by the server (`Content-Length`, `DownloadInfoDto`'s
    /// per-archive `size`, or the asset's `fileSizeInByte`); `0` when it
    /// announced none. Written by the progress callback, which is the only
    /// place that learns a length the request did not carry.
    var expectedBytes: Int64
    var receivedBytes: Int64
    var status: DownloadStatus
    var errorMessage: String?
    /// Where the finished file landed — `nil` until it is on disk.
    var destinationURL: URL?

    init(
        id: String,
        assetId: String,
        fileName: String,
        isArchive: Bool = false,
        expectedBytes: Int64 = 0,
        receivedBytes: Int64 = 0,
        status: DownloadStatus = .queued,
        errorMessage: String? = nil,
        destinationURL: URL? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.fileName = fileName
        self.isArchive = isArchive
        self.expectedBytes = expectedBytes
        self.receivedBytes = receivedBytes
        self.status = status
        self.errorMessage = errorMessage
        self.destinationURL = destinationURL
    }

    /// 0...1 once the server announced a length, `nil` when it announced none
    /// — the bar is then indeterminate rather than frozen at 0 %, the same
    /// convention as `OfflineDownloadViewModel.progress(for:)`.
    var progress: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }

    /// The size the row displays: what was announced, else what has arrived so
    /// far. Formatting goes through `ByteCountFormatter` — the repo has no
    /// second byte formatter (`OfflineDownloadViewModel.formattedUsage(_:)`).
    var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: expectedBytes > 0 ? expectedBytes : receivedBytes,
            countStyle: .file
        )
    }
}
