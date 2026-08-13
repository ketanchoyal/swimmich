import CryptoKit
import Foundation
import XCTest
@testable import ImmichSwiftUI

final class BackupEngineTests: XCTestCase {

    private func candidate(
        _ id: String,
        kind: BackupAssetKind = .image,
        album: String? = nil,
        favorite: Bool = false
    ) -> BackupCandidate {
        BackupCandidate(
            id: id, kind: kind,
            fileName: "\(id).jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z",
            duration: kind == .video ? 12 : nil,
            isFavorite: favorite,
            albumName: album
        )
    }

    private func settings(
        enabled: Bool = true,
        wifi: Bool = false,
        charging: Bool = false,
        screenshots: Bool = false,
        albums: Set<String> = []
    ) -> BackupSettings {
        BackupSettings(
            isEnabled: enabled,
            onlyOnWiFi: wifi,
            onlyWhenCharging: charging,
            excludeScreenshots: screenshots,
            selectedAlbumIDs: albums
        )
    }

    // MARK: - Cœur: dédup + upload + progression

    @MainActor
    func test_backup_acceptAndRejectMix() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1"), candidate("c2"), candidate("c3")]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [
                AssetBulkUploadCheckResponse.Result(id: "c1", action: "accept"),
                AssetBulkUploadCheckResponse.Result(id: "c2", action: "reject", reason: "duplicate"),
                AssetBulkUploadCheckResponse.Result(id: "c3", action: "accept"),
            ]
        )
        let env = MockBackupEnvironment()
        let engine = BackupEngine(client: mock, source: source, environment: env)

        await engine.run(settings: settings())

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.uploadedCount, 2)
        XCTAssertEqual(engine.rejectedCount, 1)
        XCTAssertEqual(engine.failedCount, 0)
        XCTAssertEqual(engine.total, 2)
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertEqual(mock.lastUploadFilename, "c3.jpg", "dernier upload = dernier accepté")
        XCTAssertNil(mock.lastUploadDuration, "image → duration nil")
    }

    @MainActor
    func test_backup_checksumSentMatchesSha1Base64() async {
        let payload = Data("hello-immich".utf8)
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        source.dataProvider = { _ in payload }
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [AssetBulkUploadCheckResponse.Result(id: "c1", action: "accept")]
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings())

        let expected = Data(Insecure.SHA1.hash(data: payload)).base64EncodedString()
        XCTAssertEqual(mock.lastUploadChecksum, expected)
        XCTAssertEqual(mock.lastUploadData, payload)
        XCTAssertEqual(mock.lastUploadFileCreatedAt, "2024-07-01T00:00:00.000Z")
        XCTAssertFalse(mock.lastUploadIsFavorite ?? true)
    }

    @MainActor
    func test_backup_videoCarriesDurationAndFavorite() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("v1", kind: .video, favorite: true)]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [AssetBulkUploadCheckResponse.Result(id: "v1", action: "accept")]
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings())

        XCTAssertEqual(mock.lastUploadDuration, 12)
        XCTAssertEqual(mock.lastUploadIsFavorite, true)
        XCTAssertEqual(mock.lastUploadVisibility, .timeline)
    }

    // MARK: - Gating environment

    @MainActor
    func test_backup_wifiGateBlocksRun() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        let env = MockBackupEnvironment()
        env.hasWiFiValue = false
        let engine = BackupEngine(client: mock, source: source, environment: env)

        await engine.run(settings: settings(wifi: true))

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.uploadedCount, 0)
        XCTAssertEqual(mock.requestCount, 0, "aucun appel réseau")
        XCTAssertEqual(engine.lastError, "Backup requires a Wi-Fi connection.")
    }

    @MainActor
    func test_backup_chargingGateBlocksRun() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        let env = MockBackupEnvironment()
        env.isChargingValue = false
        let engine = BackupEngine(client: mock, source: source, environment: env)

        await engine.run(settings: settings(charging: true))

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(mock.requestCount, 0)
        XCTAssertEqual(engine.lastError, "Backup requires charging.")
    }

    @MainActor
    func test_backup_disabledIsNoOp() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings(enabled: false))

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(mock.requestCount, 0)
    }

    // MARK: - Cancellation

    @MainActor
    func test_backup_cancelBeforeRun() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1"), candidate("c2")]
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        engine.cancel()
        await engine.run(settings: settings())

        XCTAssertEqual(engine.phase, .cancelled)
        XCTAssertEqual(mock.requestCount, 0)
    }

    @MainActor
    func test_backup_cancelMidUploadStopsAtItemBoundary() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1"), candidate("c2"), candidate("c3")]
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())
        source.onFirstLoad = { engine.cancel() }

        await engine.run(settings: settings())

        XCTAssertEqual(engine.phase, .cancelled)
        XCTAssertLessThan(engine.uploadedCount, 3, "stoppé au premier élément")
    }

    // MARK: - Erreurs

    @MainActor
    func test_backup_uploadFailureContinuesToNextItem() async {
        let mock = MockImmichClient()
        mock.uploadError = APIError.serverError(500, "boom")
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1"), candidate("c2")]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [
                AssetBulkUploadCheckResponse.Result(id: "c1", action: "accept"),
                AssetBulkUploadCheckResponse.Result(id: "c2", action: "accept"),
            ]
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings())

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.failedCount, 2)
        XCTAssertEqual(engine.uploadedCount, 0)
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertEqual(engine.lastError, "Server error 500: boom")
    }

    @MainActor
    func test_backup_loadFailureCountsFailedAndContinues() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("bad"), candidate("good")]
        source.loadError = APIError.decoding("PHAsset not found")
        // loadError s'applique au premier loadData seulement? Non — tous.
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings())

        XCTAssertEqual(engine.failedCount, 2, "tous les loads échouent")
        XCTAssertEqual(engine.uploadedCount, 0)
        XCTAssertEqual(engine.phase, .done)
    }

    // MARK: - Filtres + scoping albums

    @MainActor
    func test_backup_excludesScreenshotsAlbum() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [
            candidate("shot", album: "Screenshots"),
            candidate("real"),
        ]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [
                AssetBulkUploadCheckResponse.Result(id: "shot", action: "accept"),
                AssetBulkUploadCheckResponse.Result(id: "real", action: "accept"),
            ]
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings(screenshots: true))

        XCTAssertEqual(engine.rejectedCount + engine.uploadedCount, 1)
        XCTAssertEqual(mock.lastUploadFilename, "real.jpg")
    }

    @MainActor
    func test_backup_keepsScreenshotsWhenNotExcluded() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("shot", album: "Screenshots")]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [AssetBulkUploadCheckResponse.Result(id: "shot", action: "accept")]
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings(screenshots: false))

        XCTAssertEqual(engine.uploadedCount, 1)
        XCTAssertEqual(mock.lastUploadFilename, "shot.jpg")
    }

    @MainActor
    func test_backup_selectedAlbumsForwardedToSource() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings(albums: ["a1", "a2"]))

        XCTAssertEqual(source.lastAlbumIDs, ["a1", "a2"])
    }

    // MARK: - Chunking

    @MainActor
    func test_backup_chunksBulkCheckBy1000() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = (0..<1250).map { candidate("c\($0)") }
        mock.bulkUploadCheckChunks = []
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: (0..<1250).map { AssetBulkUploadCheckResponse.Result(id: "c\($0)", action: "accept") }
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings())

        XCTAssertEqual(mock.bulkUploadCheckChunks.count, 2, "1000 + 250")
        XCTAssertEqual(mock.bulkUploadCheckChunks[0].count, 1000)
        XCTAssertEqual(mock.bulkUploadCheckChunks[1].count, 250)
        XCTAssertEqual(engine.uploadedCount, 1250)
    }

    // MARK: - Live Activity progress hook (P2 backup-live-activity)

    @MainActor
    func test_backupEngine_onProgressHookFiresSequence() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1"), candidate("c2"), candidate("c3")]
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: (1...3).map { AssetBulkUploadCheckResponse.Result(id: "c\($0)", action: "accept") }
        )
        let engine = BackupEngine(client: mock, source: source, environment: MockBackupEnvironment())
        var progressCalls: [(uploaded: Int, total: Int)] = []
        engine.onProgressUpdate = { uploaded, total in
            progressCalls.append((uploaded, total))
        }

        await engine.run(settings: settings())

        XCTAssertEqual(progressCalls.count, 4, "début + 3 items")
        XCTAssertEqual(progressCalls[0].uploaded, 0)
        XCTAssertEqual(progressCalls[0].total, 3)
        XCTAssertEqual(progressCalls[3].uploaded, 3)
        XCTAssertEqual(progressCalls[3].total, 3)
    }
}

// MARK: - Settings store (persistence)

final class BackupSettingsStoreTests: XCTestCase {

    @MainActor
    func test_settings_persistAcrossInstances() {
        let suite = "backup-settings-test-\(UUID().uuidString)"
        let first = BackupSettingsStore(suiteName: suite)
        first.isEnabled = true
        first.onlyOnWiFi = true
        first.onlyWhenCharging = true
        first.excludeScreenshots = true
        first.selectedAlbumIDs = ["a1", "a2"]

        let second = BackupSettingsStore(suiteName: suite)
        XCTAssertTrue(second.isEnabled)
        XCTAssertTrue(second.onlyOnWiFi)
        XCTAssertTrue(second.onlyWhenCharging)
        XCTAssertTrue(second.excludeScreenshots)
        XCTAssertEqual(second.selectedAlbumIDs, ["a1", "a2"])
        XCTAssertEqual(second.snapshot().selectedAlbumIDs, ["a1", "a2"])
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @MainActor
    func test_settings_defaultsAreOff() {
        let suite = "backup-settings-test-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        XCTAssertFalse(store.isEnabled)
        XCTAssertFalse(store.onlyOnWiFi)
        XCTAssertFalse(store.onlyWhenCharging)
        XCTAssertFalse(store.excludeScreenshots)
        XCTAssertTrue(store.selectedAlbumIDs.isEmpty)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @MainActor
    func test_viewModel_runBackupSubmitsSchedulerOnDone() async {
        let mockClient = MockImmichClient()
        let photos = MockPhotoLibraryService()
        let scheduler = MockBackupScheduler()
        let engine = BackupEngine(client: mockClient, source: MockBackupAssetSource(), environment: MockBackupEnvironment())
        let settings = BackupSettingsStore(suiteName: "backup-vm-test-\(UUID().uuidString)")
        settings.isEnabled = true
        let activity = MockBackupLiveActivityService()
        let vm = UploadViewModel(client: mockClient, photos: photos, engine: engine, settings: settings, scheduler: scheduler, activityService: activity)

        await vm.runBackup()

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(scheduler.submitCount, 1)
        UserDefaults(suiteName: "backup-vm-test-\(UUID().uuidString)")?.removePersistentDomain(forName: "backup-vm-test-\(UUID().uuidString)")
    }
}