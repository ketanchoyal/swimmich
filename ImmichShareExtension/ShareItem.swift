import Foundation

/// One attachment the user handed to the sheet, already staged inside the
/// extension's own container: the host app's copy is only readable while the
/// provider's completion handler runs, so `ShareViewController` copies it out
/// before anything else happens.
struct ShareItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let filename: String
    /// The staged copy, inside the extension's temporary directory.
    let fileURL: URL
    let isVideo: Bool
    let byteCount: Int
    /// Creation instant of the staged copy, sent as `fileCreatedAt`. A share
    /// carries no Photos metadata (that would need a library permission for a
    /// file the user just handed us), so this is when the sheet received it.
    let createdAt: Date
    /// Whole seconds for a movie, nil for a photo (`duration` form field).
    let duration: Int?
    var isSelected: Bool
    var status: ShareItemStatus

    /// Sent as the upload's `deviceAssetId`. A share has no Photos identifier
    /// to hand over, and a fresh one per share keeps the server's per-device
    /// asset listing meaningful without colliding with a backup entry.
    var deviceAssetId: String { "share/\(id.uuidString)" }

    /// Human-readable size, composed here so the view never formats a number
    /// (the row is a projection, not a formatter).
    var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

/// Mirrors the four states of the Flutter upload row
/// (`mobile/lib/pages/share_intent/share_intent.page.dart`): queued, running
/// with a progress fraction, done with the asset it produced, failed with the
/// server's own message.
enum ShareItemStatus: Equatable, Sendable {
    case enqueued
    case running(Double)
    case complete(assetId: String)
    case failed(String)
}

extension ShareItemStatus {
    /// Whether the item still needs to be sent: queued, or a previous failure
    /// the user may retry.
    var isPending: Bool {
        switch self {
        case .enqueued, .failed: return true
        case .running, .complete: return false
        }
    }

    /// 0…1 for the row's determinate progress bar.
    var fraction: Double {
        switch self {
        case .running(let value): return min(max(value, 0), 1)
        case .complete: return 1
        case .enqueued, .failed: return 0
        }
    }

    /// True once the item can no longer change on its own.
    var isTerminal: Bool {
        switch self {
        case .complete, .failed: return true
        case .enqueued, .running: return false
        }
    }
}
