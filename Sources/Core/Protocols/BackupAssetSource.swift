import Foundation
import Photos

/// Kind of a backup candidate (PHAsset mediaType, mapped).
enum BackupAssetKind: String, Sendable {
    case image
    case video
}

/// A library asset reduced to its backup-relevant metadata — value type so the
/// whole engine is testable without constructing a real `PHAsset`.
struct BackupCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let kind: BackupAssetKind
    let fileName: String
    let fileCreatedAt: String
    let fileModifiedAt: String
    let duration: Int?
    let isFavorite: Bool
    /// Source album display name (nil when not member of any user album).
    let albumName: String?
}

/// A user-visible album the user can scope backups to.
struct BackupAlbum: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let count: Int
}

/// Asset source for the backup engine — PHPhotoLibrary behind value types.
/// Tests provide a pure mock; production uses `PhotoLibraryServiceImpl`.
protocol BackupAssetSource: Sendable {
    func fetchAlbums() -> [BackupAlbum]
    /// Candidates sorted by creation date DESC. Empty `albumIDs` = whole library.
    func fetchCandidates(in albumIDs: Set<String>) -> [BackupCandidate]
    func loadData(for candidate: BackupCandidate) async throws -> Data
}