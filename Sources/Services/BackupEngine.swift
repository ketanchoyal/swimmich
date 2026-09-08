import CryptoKit
import Foundation

/// Upload conditions + scoping, persisted by `BackupSettingsStore`.
struct BackupSettings: Equatable, Sendable {
    var isEnabled = false
    var excludeCameraRoll = false
    var excludeWhatsApp = false
    /// Foreground auto-run gate: when on, app activation runs a scan (in
    /// addition to the OS background windows). See
    /// `UploadViewModel.kickOffAutoBackupIfConfigured`.
    var autoDetectNewPhotos = false
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

    init(
        client: any ImmichClient,
        source: any BackupAssetSource,
        environment: any BackupEnvironment = SystemBackupEnvironment()
    ) {
        self.client = client
        self.source = source
        self.environment = environment
    }

    /// Async-cancellation — no preconditions, engine decides at the next item
    /// boundary. Call from a BG expiration handler.
    func cancel() {
        isCancelled = true
    }

    /// Surfaces a pre-run error to the UI (e.g. missing Photos permission)
    /// without entering the pipeline.
    func reportError(_ message: String) {
        lastError = message
    }

    /// Runs the backup pipeline. `manual == true` (Run now / resume /
    /// backfill) is an explicit user action: it ignores the automatic gates
    /// (isEnabled, Wi-Fi-only, charging-only), which only govern the
    /// unattended background path (`manual == false`).
    ///
    /// The pipeline is memory-bounded like the upstream Flutter client: each
    /// candidate's original is streamed to a temp file on disk, SHA1-hashed by
    /// streaming that file, then the temp file is released. Accepted assets are
    /// re-exported and uploaded one at a time, streaming straight from disk —
    /// so no original (nor the multipart body) is ever fully held in memory,
    /// and even multi-GB videos back up without an OOM. Dedup is batched in
    /// `checkChunkSize` chunks (checksums only), keeping progress live.
    func run(settings: BackupSettings, manual: Bool = false) async {
        guard !(isCancelled || phase == .uploading || phase == .checking) else {
            if isCancelled { phase = .cancelled }
            return
        }
        if !manual {
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
        }
        reset()
        lastError = nil
        phase = .checking
        var remaining = source.fetchCandidates(in: settings.selectedAlbumIDs)
        if settings.excludeScreenshots {
            remaining = remaining.filter { $0.albumName != screenshotsAlbumName }
        }
        if settings.excludeCameraRoll {
            remaining = remaining.filter { !$0.fileName.hasPrefix("IMG_") }
        }
        if settings.excludeWhatsApp {
            remaining = remaining.filter { !$0.fileName.contains("WhatsApp") }
        }

        var batch: [(candidate: BackupCandidate, checksum: String)] = []
        var index = 0
        while index < remaining.count {
            if isCancelled {
                phase = .cancelled
                onProgressUpdate?(uploadedCount, total)
                return
            }
            let candidate = remaining[index]
            index += 1
            do {
                let fileURL = try await source.exportOriginal(for: candidate)
                let checksum: String
                do {
                    checksum = try Self.streamingSHA1Base64(fileURL)
                } catch {
                    try? FileManager.default.removeItem(at: fileURL)
                    throw error
                }
                // Hash pass keeps only the checksum; the temp file is released
                // now and the original is re-exported at upload time.
                try? FileManager.default.removeItem(at: fileURL)
                batch.append((candidate, checksum))
            } catch {
                failedCount += 1
                lastError = error.localizedDescription
                guard !isCancelled else { phase = .cancelled; return }
                continue
            }
            if batch.count == Self.checkChunkSize {
                await processBatch(&batch)
                if isCancelled {
                    phase = .cancelled
                    onProgressUpdate?(uploadedCount, total)
                    return
                }
            }
        }
        if !batch.isEmpty, !isCancelled {
            await processBatch(&batch)
        }
        phase = isCancelled ? .cancelled : .done
    }

    /// Dedup-checks one batch of checksums against the server, then re-exports
    /// and uploads each accepted candidate one at a time, streaming from disk
    /// and deleting the temp file after each. `total` — hence upload progress —
    /// grows as accepted assets are discovered, so progress is live from the
    /// first upload, not after the whole library has been scanned.
    private func processBatch(_ batch: inout [(candidate: BackupCandidate, checksum: String)]) async {
        defer { batch.removeAll() }
        let items = batch.map {
            AssetBulkUploadCheckRequest.Item(id: $0.candidate.id, checksum: $0.checksum)
        }
        var acceptIDs: Set<String> = []
        do {
            let response = try await client.bulkUploadCheck(AssetBulkUploadCheckRequest(assets: items))
            for result in response.results {
                if result.action == "accept" {
                    acceptIDs.insert(result.id)
                } else {
                    rejectedCount += 1
                }
            }
        } catch {
            failedCount += batch.count
            lastError = error.localizedDescription
            guard !isCancelled else { phase = .cancelled; return }
            return
        }
        guard !acceptIDs.isEmpty else { return }
        for entry in batch where acceptIDs.contains(entry.candidate.id) {
            if isCancelled {
                phase = .cancelled
                onProgressUpdate?(uploadedCount, total)
                return
            }
            if phase != .uploading {
                phase = .uploading
            }
            total += 1
            do {
                let fileURL = try await source.exportOriginal(for: entry.candidate)
                do {
                    _ = try await client.uploadAsset(
                        fileURL: fileURL,
                        fileCreatedAt: entry.candidate.fileCreatedAt,
                        fileModifiedAt: entry.candidate.fileModifiedAt,
                        filename: entry.candidate.fileName,
                        duration: entry.candidate.duration,
                        isFavorite: entry.candidate.isFavorite,
                        visibility: .timeline,
                        livePhotoVideoId: nil,
                        checksum: entry.checksum
                    )
                    uploadedCount += 1
                } catch {
                    failedCount += 1
                    lastError = error.localizedDescription
                }
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                failedCount += 1
                lastError = error.localizedDescription
            }
            currentIndex += 1
            onProgressUpdate?(uploadedCount, total)
        }
    }

    /// base64-encoded SHA1 of a file's bytes (matches `x-immich-checksum`),
    /// computed by streaming the file in 1 MiB chunks — never loads the whole
    /// file into memory.
    nonisolated static func streamingSHA1Base64(_ fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).base64EncodedString()
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