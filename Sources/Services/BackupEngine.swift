import CryptoKit
import Foundation

/// Upload conditions + scoping, persisted by `BackupSettingsStore`.
struct BackupSettings: Equatable, Sendable {
    var isEnabled = false
    var onlyOnWiFi = false
    var onlyWhenCharging = false
    var excludeScreenshots = false
    var selectedAlbumIDs: Set<String> = []
}

/// Screenshot album name — the convention `PhotoLibraryServiceImpl` sets on
/// candidates; the engine drops candidates carrying it when excluded.
private let screenshotsAlbumName = "Screenshots"

/// Background backup state machine. Pure orchestration over the injected
/// seams: `ImmichClient` (dedup + upload), `BackupAssetSource` (library),
/// `BackupEnvironment` (wifi/charging gates).
@Observable
@MainActor
final class BackupEngine {
    enum Phase: Equatable {
        case idle, checking, uploading, done, cancelled
    }

    let client: any ImmichClient
    let source: any BackupAssetSource
    let environment: any BackupEnvironment

    private(set) var phase: Phase = .idle
    private(set) var total = 0
    private(set) var currentIndex = 0
    private(set) var uploadedCount = 0
    private(set) var rejectedCount = 0
    private(set) var failedCount = 0
    private(set) var lastError: String?

    /// Progress callback (uploaded, total) fired on the main actor at the
    /// start of the upload phase and after every item. Live Activity driver.
    var onProgressUpdate: ((_ uploaded: Int, _ total: Int) -> Void)?

    private var isCancelled = false
    private static let checkChunkSize = 1000

    init(client: any ImmichClient, source: any BackupAssetSource, environment: any BackupEnvironment = SystemBackupEnvironment()) {
        self.client = client
        self.source = source
        self.environment = environment
    }

    /// Async-cancellation — no preconditions, engine decides at the next item
    /// boundary. Call from a BG expiration handler.
    func cancel() {
        isCancelled = true
    }

    func run(settings: BackupSettings) async {
        guard !(isCancelled || phase == .uploading || phase == .checking) else {
            if isCancelled { phase = .cancelled }
            return
        }
        guard settings.isEnabled else { return }

        // Environment gates — phase stays idle, nothing hits the network.
        if settings.onlyOnWiFi && !environment.hasWiFiConnection {
            lastError = "Backup requires a Wi-Fi connection."
            return
        }
        if settings.onlyWhenCharging && !environment.isCharging {
            lastError = "Backup requires charging."
            return
        }

        reset()
        lastError = nil
        phase = .checking

        var candidates = source.fetchCandidates(in: settings.selectedAlbumIDs)
        if settings.excludeScreenshots {
            candidates = candidates.filter { $0.albumName != screenshotsAlbumName }
        }

        // Resolve checksums + payloads once (loadData is expensive).
        var dataByID: [String: Data] = [:]
        var items: [AssetBulkUploadCheckRequest.Item] = []
        for candidate in candidates {
            do {
                let data = try await source.loadData(for: candidate)
                dataByID[candidate.id] = data
                items.append(
                    AssetBulkUploadCheckRequest.Item(
                        id: candidate.id,
                        checksum: Self.sha1Base64(data)
                    )
                )
            } catch {
                failedCount += 1
                lastError = error.localizedDescription
                guard !isCancelled else { phase = .cancelled; return }
            }
        }
        guard !isCancelled else { phase = .cancelled; return }

        // Server-side dedup, chunked.
        var acceptIDs: [String] = []
        for chunk in stride(from: 0, to: items.count, by: Self.checkChunkSize) {
            let slice = Array(items[chunk..<min(chunk + Self.checkChunkSize, items.count)])
            do {
                let response = try await client.bulkUploadCheck(AssetBulkUploadCheckRequest(assets: slice))
                for result in response.results {
                    if result.action == "accept" { acceptIDs.append(result.id) } else { rejectedCount += 1 }
                }
            } catch {
                failedCount += slice.count
                lastError = error.localizedDescription
                guard !isCancelled else { phase = .cancelled; return }
            }
        }
        guard !isCancelled else { phase = .cancelled; return }

        var accepted: [BackupCandidate] = []
        let acceptSet = Set(acceptIDs)
        for candidate in candidates where acceptSet.contains(candidate.id) {
            accepted.append(candidate)
        }

        phase = .uploading
        total = accepted.count
        onProgressUpdate?(0, total)
        for candidate in accepted {
            if isCancelled { phase = .cancelled; onProgressUpdate?(uploadedCount, total); return }
            guard let data = dataByID[candidate.id] else {
                failedCount += 1
                currentIndex += 1
                onProgressUpdate?(uploadedCount, total)
                continue
            }
            do {
                _ = try await client.uploadAsset(
                    data: data,
                    fileCreatedAt: candidate.fileCreatedAt,
                    fileModifiedAt: candidate.fileModifiedAt,
                    filename: candidate.fileName,
                    duration: candidate.duration,
                    isFavorite: candidate.isFavorite,
                    visibility: .timeline,
                    livePhotoVideoId: nil,
                    checksum: Self.sha1Base64(data)
                )
                uploadedCount += 1
            } catch {
                failedCount += 1
                lastError = error.localizedDescription
            }
            currentIndex += 1
            onProgressUpdate?(uploadedCount, total)
        }
        phase = isCancelled ? .cancelled : .done
    }

    /// base64-encoded SHA1 (matches `x-immich-checksum`).
    nonisolated static func sha1Base64(_ data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    private func reset() {
        isCancelled = false
        total = 0
        currentIndex = 0
        uploadedCount = 0
        rejectedCount = 0
        failedCount = 0
    }
}