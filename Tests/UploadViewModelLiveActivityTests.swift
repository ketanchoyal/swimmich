import XCTest
@testable import ImmichSwiftUI

/// Live Activity lifecycle driven by `UploadViewModel.runBackup()` (P2
/// backup-live-activity). ActivityKit itself is never touched — the service
/// seam is a recorder.
final class UploadViewModelLiveActivityTests: XCTestCase {

    @MainActor
    private func makeAcceptedClient(candidates: [String]) -> MockImmichClient {
        let mock = MockImmichClient()
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: candidates.map { AssetBulkUploadCheckResponse.Result(id: $0, action: "accept") }
        )
        return mock
    }

    @MainActor
    private func makeEngine(client: MockImmichClient, candidates: [String]) -> BackupEngine {
        let source = MockBackupAssetSource()
        source.candidates = candidates.map { id in
            BackupCandidate(
                id: id, kind: .image, fileName: "\(id).jpg",
                fileCreatedAt: "2024-07-01T00:00:00.000Z",
                fileModifiedAt: "2024-07-01T00:00:00.000Z",
                duration: nil, isFavorite: false, albumName: nil
            )
        }
        return BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
    }

    @MainActor
    private func makeEnabledStore() -> BackupSettingsStore {
        let suite = "backup-live-vm-\(UUID().uuidString)"
        let store = BackupSettingsStore(suiteName: suite)
        store.isEnabled = true
        return store
    }

    @MainActor
    func test_liveActivity_startThenUpdateThenEndOnDone() async {
        let client = makeAcceptedClient(candidates: ["c1", "c2", "c3"])
        let engine = makeEngine(client: client, candidates: ["c1", "c2", "c3"])
        let scheduler = MockBackupScheduler()
        let activity = MockBackupLiveActivityService()
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(),
            engine: engine, settings: makeEnabledStore(),
            scheduler: scheduler, activityService: activity
        )

        await vm.runBackup()

        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(activity.startCalls.count, 1)
        XCTAssertEqual(activity.startCalls[0].total, 0, "total inconnu avant dédup")
        XCTAssertEqual(activity.updateCalls.count, 4, "début + 3 items")
        XCTAssertEqual(activity.updateCalls[0].total, 3)
        XCTAssertEqual(activity.updateCalls[3].uploaded, 3)
        XCTAssertEqual(activity.endCalls.count, 1)
        XCTAssertEqual(activity.endCalls[0].uploaded, 3)
        XCTAssertEqual(activity.endCalls[0].total, 3)
        XCTAssertEqual(activity.endCalls[0].success, true)
        XCTAssertEqual(scheduler.submitCount, 1)
    }

    @MainActor
    func test_liveActivity_cancelEndsWithFailure() async {
        let client = makeAcceptedClient(candidates: ["c1"])
        let source = MockBackupAssetSource()
        source.candidates = [BackupCandidate(
            id: "c1", kind: .image, fileName: "c1.jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z",
            duration: nil, isFavorite: false, albumName: nil
        )]
        let engine = BackupEngine(client: client, source: source, environment: MockBackupEnvironment())
        source.onFirstLoad = { [weak engine] in
            engine?.cancel()
        }
        let scheduler = MockBackupScheduler()
        let activity = MockBackupLiveActivityService()
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(),
            engine: engine, settings: makeEnabledStore(),
            scheduler: scheduler, activityService: activity
        )

        await vm.runBackup()

        XCTAssertEqual(engine.phase, .cancelled)
        XCTAssertEqual(activity.endCalls.count, 1)
        XCTAssertEqual(activity.endCalls[0].success, false)
        XCTAssertEqual(scheduler.submitCount, 0, "pas de reschedule après annulation")
    }

    @MainActor
    func test_liveActivity_disabledSettingsNoUpdatesNoEnd() async {
        let client = makeAcceptedClient(candidates: ["c1"])
        let engine = makeEngine(client: client, candidates: ["c1"])
        let store = makeEnabledStore()
        store.isEnabled = false
        let activity = MockBackupLiveActivityService()
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(),
            engine: engine, settings: store,
            scheduler: MockBackupScheduler(), activityService: activity
        )

        await vm.runBackup()

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(activity.startCalls.count, 1, "Live Activity démarré, puis jamais mis à jour")
        XCTAssertTrue(activity.updateCalls.isEmpty)
        XCTAssertTrue(activity.endCalls.isEmpty)
    }

    @MainActor
    func test_liveActivity_wifiGateBlocksNoUpdates() async {
        let client = makeAcceptedClient(candidates: ["c1"])
        let engine = makeEngine(client: client, candidates: ["c1"])
        let store = makeEnabledStore()
        store.onlyOnWiFi = true
        let env = MockBackupEnvironment()
        env.hasWiFiValue = false
        let engineWifi = BackupEngine(client: client, source: MockBackupAssetSource(), environment: env)
        let activity = MockBackupLiveActivityService()
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(),
            engine: engineWifi, settings: store,
            scheduler: MockBackupScheduler(), activityService: activity
        )

        await vm.runBackup()

        XCTAssertEqual(engineWifi.phase, .idle)
        XCTAssertEqual(engineWifi.lastError, "Backup requires a Wi-Fi connection.")
        XCTAssertTrue(activity.updateCalls.isEmpty)
        XCTAssertTrue(activity.endCalls.isEmpty)
    }

    @MainActor
    func test_liveActivity_hookClearedAfterRun() async {
        let client = makeAcceptedClient(candidates: ["c1"])
        let engine = makeEngine(client: client, candidates: ["c1"])
        let vm = UploadViewModel(
            client: client, photos: MockPhotoLibraryService(),
            engine: engine, settings: makeEnabledStore(),
            scheduler: MockBackupScheduler(), activityService: MockBackupLiveActivityService()
        )

        await vm.runBackup()

        XCTAssertNil(engine.onProgressUpdate, "le hook est retiré en fin de run")
    }
}