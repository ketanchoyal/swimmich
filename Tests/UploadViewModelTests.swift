import Foundation
import XCTest
@testable import ImmichSwiftUI

// MARK: - BackupSettingsStore new fields (AC-BK01, AC-BK02)

final class BackupSettingsNewFieldsTests: XCTestCase {

    @MainActor
    func test_settingsStore_exposesExcludeCameraRoll() {
        let suite = "backup-cameraroll-test-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        XCTAssertFalse(store.excludeCameraRoll)
        store.excludeCameraRoll = true
        let fresh = BackupSettingsStore(suiteName: suite)
        XCTAssertTrue(fresh.excludeCameraRoll)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @MainActor
    func test_settingsStore_exposesExcludeWhatsApp() {
        let suite = "backup-whatsapp-test-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        XCTAssertFalse(store.excludeWhatsApp)
        store.excludeWhatsApp = true
        let fresh = BackupSettingsStore(suiteName: suite)
        XCTAssertTrue(fresh.excludeWhatsApp)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @MainActor
    func test_settingsStore_exposesAutoDetectNewPhotos() {
        let suite = "backup-autodetect-test-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        XCTAssertFalse(store.autoDetectNewPhotos)
        store.autoDetectNewPhotos = true
        let fresh = BackupSettingsStore(suiteName: suite)
        XCTAssertTrue(fresh.autoDetectNewPhotos)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @MainActor
    func test_snapshot_includesNewFields() {
        let suite = "backup-snapshot-test-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        store.excludeCameraRoll = true
        store.excludeWhatsApp = true
        store.autoDetectNewPhotos = true
        let snap = store.snapshot()
        XCTAssertTrue(snap.excludeCameraRoll)
        XCTAssertTrue(snap.excludeWhatsApp)
        XCTAssertTrue(snap.autoDetectNewPhotos)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

// MARK: - Helpers

private func makeCandidate(id: String, fileName: String) -> BackupCandidate {
    BackupCandidate(
        id: id, kind: .image, fileName: fileName,
        fileCreatedAt: "2024-01-01T00:00:00.000Z",
        fileModifiedAt: "2024-01-01T00:00:00.000Z",
        duration: nil, isFavorite: false, albumName: nil
    )
}

@MainActor
private func makeVM(
    client: MockImmichClient,
    source: MockBackupAssetSource,
    settings: BackupSettingsStore,
    photos: MockPhotoLibraryService = MockPhotoLibraryService()
) -> (UploadViewModel, BackupEngine) {
    let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
    let vm = UploadViewModel(
        client: client, photos: photos, engine: engine, settings: settings,
        scheduler: MockBackupScheduler(), activityService: MockBackupLiveActivityService()
    )
    return (vm, engine)
}

// MARK: - UploadViewModel new features (AC-BK03)

final class UploadViewModelNewFeaturesTests: XCTestCase {

    @MainActor
    func test_viewModel_canResumeAfterCompletedRun() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "c1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "c1", fileName: "photo.jpg")]
        source.dataProvider = { _ in Data(repeating: 0, count: 8) }
        let settings = BackupSettingsStore(suiteName: "vm-resume-\(UUID().uuidString)")
        settings.isEnabled = true
        let (vm, engine) = makeVM(client: client, source: source, settings: settings)

        XCTAssertFalse(vm.canResume)
        await vm.runBackup()
        XCTAssertEqual(engine.phase, .done)
        XCTAssertTrue(vm.canResume)
    }

    @MainActor
    func test_viewModel_showBackfillSheet() {
        let settings = BackupSettingsStore(suiteName: "vm-sheet-\(UUID().uuidString)")
        let (vm, _) = makeVM(client: MockImmichClient(), source: MockBackupAssetSource(), settings: settings)
        XCTAssertFalse(vm.showBackfillSheet)
        vm.showBackfillSheet = true
        XCTAssertTrue(vm.showBackfillSheet)
    }

    @MainActor
    func test_viewModel_sharesSettingsStore() {
        // The view binds toggles to $vm.settings.*; the VM must run the
        // engine against that same store, so a toggle flows into the snapshot.
        let settings = BackupSettingsStore(suiteName: "vm-backfill-\(UUID().uuidString)")
        let (vm, _) = makeVM(client: MockImmichClient(), source: MockBackupAssetSource(), settings: settings)
        vm.settings.excludeCameraRoll = true
        vm.settings.excludeWhatsApp = true
        vm.settings.autoDetectNewPhotos = true
        let snap = vm.settings.snapshot()
        XCTAssertTrue(snap.excludeCameraRoll)
        XCTAssertTrue(snap.excludeWhatsApp)
        XCTAssertTrue(snap.autoDetectNewPhotos)
    }

    @MainActor
    func test_viewModel_uploadHistory_populatedOnDone() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "c1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "c1", fileName: "photo1.jpg")]
        source.dataProvider = { _ in Data(repeating: 0, count: 100) }
        let settings = BackupSettingsStore(suiteName: "vm-history-\(UUID().uuidString)")
        settings.isEnabled = true
        let (vm, _) = makeVM(client: client, source: source, settings: settings)

        await vm.runBackup()

        XCTAssertEqual(vm.uploadHistory.count, 1)
        let entry = vm.uploadHistory[0]
        XCTAssertTrue(entry.success)
        XCTAssertEqual(entry.uploaded, 1)
        XCTAssertEqual(entry.total, 1)
        XCTAssertEqual(entry.failed, 0)
    }

    @MainActor
    func test_runBackfill_scopesToAlbumAndUploads() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "a1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "a1", fileName: "album-photo.jpg")]
        source.dataProvider = { _ in Data(repeating: 1, count: 64) }
        // Auto-backup OFF: backfill must still run (manual, forced).
        let settings = BackupSettingsStore(suiteName: "vm-backfill-run-\(UUID().uuidString)")
        settings.isEnabled = false
        let (vm, engine) = makeVM(client: client, source: source, settings: settings)

        vm.runBackfill(albumId: "album-42")
        // runBackfill kicks off a detached Task; await completion.
        await vm.awaitCurrentBackup()

        XCTAssertEqual(source.lastAlbumIDs, ["album-42"], "backfill scopes fetch to the chosen album")
        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.uploadedCount, 1)
        XCTAssertFalse(vm.showBackfillSheet)
    }
}

// MARK: - Manual vs automatic gating (core Run-now fix)

final class BackupManualRunTests: XCTestCase {

    /// Automatic path (BGTask) with auto-backup OFF must not run.
    @MainActor
    func test_automaticRun_disabled_doesNothing() async {
        let client = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "x1", fileName: "photo.jpg")]
        let settings = BackupSettingsStore(suiteName: "auto-off-\(UUID().uuidString)")
        settings.isEnabled = false
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings.snapshot(), manual: false)

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertTrue(client.bulkUploadCheckChunks.isEmpty)
    }

    /// Manual "Run now" with auto-backup OFF must still run the pipeline.
    @MainActor
    func test_manualRun_disabled_stillRuns() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "x1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "x1", fileName: "photo.jpg")]
        source.dataProvider = { _ in Data(repeating: 2, count: 32) }
        let settings = BackupSettingsStore(suiteName: "manual-off-\(UUID().uuidString)")
        settings.isEnabled = false
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings.snapshot(), manual: true)

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.uploadedCount, 1)
    }

    /// Manual run ignores the Wi-Fi gate even with no Wi-Fi.
    @MainActor
    func test_manualRun_ignoresWiFiGate() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "x1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "x1", fileName: "photo.jpg")]
        source.dataProvider = { _ in Data(repeating: 3, count: 16) }
        let env = MockBackupEnvironment()
        env.hasWiFiValue = false
        let settings = BackupSettingsStore(suiteName: "manual-nowifi-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.onlyOnWiFi = true
        let engine = BackupEngine(client: client, source: source, environment: env)

        await engine.run(settings: settings.snapshot(), manual: true)

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.uploadedCount, 1)
    }

    /// Automatic run with Wi-Fi-only + no Wi-Fi is blocked with an error.
    @MainActor
    func test_automaticRun_wifiGateBlocks() async {
        let client = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "x1", fileName: "photo.jpg")]
        let env = MockBackupEnvironment()
        env.hasWiFiValue = false
        let settings = BackupSettingsStore(suiteName: "auto-nowifi-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.onlyOnWiFi = true
        let engine = BackupEngine(client: client, source: source, environment: env)

        await engine.run(settings: settings.snapshot(), manual: false)

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNotNil(engine.lastError)
    }
}

// MARK: - BackupEngine exclusion filtering (AC-BK02 runtime)

final class BackupEngineExclusionTests: XCTestCase {

    /// WhatsApp files are dropped before the dedup check.
    @MainActor
    func test_engine_filtersWhatsAppFiles() async {
        let client = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [
            makeCandidate(id: "w1", fileName: "WhatsApp/IMG_123.jpg"),
            makeCandidate(id: "n1", fileName: "photo.jpg")
        ]
        source.dataProvider = { _ in Data(repeating: 0, count: 50) }
        let settings = BackupSettingsStore(suiteName: "eng-wa-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.excludeWhatsApp = true
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings.snapshot())

        let checkedIDs = client.bulkUploadCheckChunks.flatMap { $0 }.map(\.id)
        XCTAssertEqual(checkedIDs, ["n1"], "the WhatsApp file is filtered out before dedup")
    }

    /// Camera-roll (IMG_) files are dropped entirely.
    @MainActor
    func test_engine_filtersCameraRollFiles() async {
        let client = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [
            makeCandidate(id: "c1", fileName: "IMG_001.jpg"),
            makeCandidate(id: "c2", fileName: "IMG_002.jpg")
        ]
        source.dataProvider = { _ in Data(repeating: 0, count: 50) }
        let settings = BackupSettingsStore(suiteName: "eng-cr-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.excludeCameraRoll = true
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())

        await engine.run(settings: settings.snapshot())

        XCTAssertTrue(client.bulkUploadCheckChunks.flatMap { $0 }.isEmpty, "all IMG_ files filtered")
        XCTAssertEqual(engine.total, 0)
    }
}

// MARK: - Auto-detect foreground kick + background chain resubmit

final class BackupAutoChainTests: XCTestCase {

    @MainActor
    func test_kick_runsGatedScanWhenAutoDetectOn() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "n1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "n1", fileName: "n1.jpg")]
        source.dataProvider = { _ in Data(repeating: 7, count: 8) }
        let settings = BackupSettingsStore(suiteName: "kick-on-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.autoDetectNewPhotos = true
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(), engine: engine, settings: settings,
            scheduler: MockBackupScheduler(), activityService: MockBackupLiveActivityService()
        )

        await vm.kickOffAutoBackupIfConfigured()
        await vm.awaitCurrentBackup()

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.uploadedCount, 1)
    }

    @MainActor
    func test_kick_noopWhenAutoDetectOff() async {
        let client = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "n1", fileName: "n1.jpg")]
        let settings = BackupSettingsStore(suiteName: "kick-off-\(UUID().uuidString)")
        settings.isEnabled = true
        settings.autoDetectNewPhotos = false
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(), engine: engine, settings: settings,
            scheduler: MockBackupScheduler(), activityService: MockBackupLiveActivityService()
        )

        await vm.kickOffAutoBackupIfConfigured()
        await vm.awaitCurrentBackup()

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(client.requestCount, 0)
    }

    @MainActor
    func test_chain_notResubmittedWhenAutoBackupOff() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "n1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "n1", fileName: "n1.jpg")]
        source.dataProvider = { _ in Data(repeating: 1, count: 4) }
        let settings = BackupSettingsStore(suiteName: "chain-off-\(UUID().uuidString)")
        settings.isEnabled = false
        let scheduler = MockBackupScheduler()
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(), engine: engine, settings: settings,
            scheduler: scheduler, activityService: MockBackupLiveActivityService()
        )

        await vm.runBackup(manual: true)

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(scheduler.submitCount, 0, "chaîne non ré-armée quand auto-backup est off")
    }

    @MainActor
    func test_chain_resubmittedAfterEnabledRun() async {
        let client = MockImmichClient()
        client.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "n1", action: "accept")]
        )
        let source = MockBackupAssetSource()
        source.candidates = [makeCandidate(id: "n1", fileName: "n1.jpg")]
        source.dataProvider = { _ in Data(repeating: 1, count: 4) }
        let settings = BackupSettingsStore(suiteName: "chain-on-\(UUID().uuidString)")
        settings.isEnabled = true
        let scheduler = MockBackupScheduler()
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(), engine: engine, settings: settings,
            scheduler: scheduler, activityService: MockBackupLiveActivityService()
        )

        await vm.runBackup(manual: true)

        XCTAssertEqual(scheduler.submitCount, 1, "un run terminé ré-arme la chaîne (auto-backup on)")
    }
}
