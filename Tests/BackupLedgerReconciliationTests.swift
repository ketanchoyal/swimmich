import Foundation
import XCTest
@testable import ImmichSwiftUI

/// The ledger is the client's dedup base. It used to have exactly one
/// invalidation path — the destructive "Reset backup tracking" button — so an
/// asset deleted server-side stayed marked as backed up, was filtered out
/// before export, and never came back. These cover the replacement: the ledger
/// stores the checksum it was uploaded under and replays it against
/// `bulk-upload-check`, at no media-byte cost.
final class BackupLedgerReconciliationTests: XCTestCase {

    private func writeLedgerFile(_ json: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ledger-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private func candidate(_ id: String, modifiedAt: String = "2024-07-01T00:00:00.000Z") -> BackupCandidate {
        BackupCandidate(
            id: id, kind: .image, fileName: "\(id).jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: modifiedAt,
            duration: nil, isFavorite: false
        )
    }

    private func settings() -> BackupSettings { BackupSettings(isEnabled: true) }

    // MARK: - File format

    /// The v1 file was a plain `[String: String]`. It must stay readable —
    /// dropping it would silently re-back-up a whole library.
    func test_ledger_v1FileLoadsWithoutChecksum() throws {
        let url = try writeLedgerFile(#"{"asset-1":"2024-01-01T00:00:00.000Z"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = BackupLedger(fileURL: url)

        XCTAssertTrue(ledger.isBackedUp(id: "asset-1", signature: "2024-01-01T00:00:00.000Z"))
        XCTAssertEqual(ledger.trackedCount(), 1)
        XCTAssertTrue(ledger.entriesForReconciliation().isEmpty,
                      "une entrée v1 n'a pas de checksum : elle n'est pas réconciliable sans re-télécharger")
        XCTAssertNil(ledger.lastReconciliation)
    }

    func test_ledger_v2RoundTripsChecksumAndLastReconciliation() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let first = BackupLedger(fileURL: url)
        first.markBackedUp(id: "asset-1", signature: "sig-1", checksum: "sum-1")
        first.recordReconciliation(at: date)
        first.save()

        // `save()` is coalesced onto a background queue; wait for the file.
        let expectation = expectation(description: "ledger flushed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        let second = BackupLedger(fileURL: url)
        XCTAssertTrue(second.isBackedUp(id: "asset-1", signature: "sig-1"))
        XCTAssertEqual(second.entriesForReconciliation().map(\.checksum), ["sum-1"])
        XCTAssertEqual(second.lastReconciliation?.timeIntervalSince1970 ?? 0,
                       date.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_ledger_unreadableFileIsTreatedAsEmpty() throws {
        let url = try writeLedgerFile("not json at all")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = BackupLedger(fileURL: url)

        XCTAssertEqual(ledger.trackedCount(), 0)
        XCTAssertFalse(ledger.isBackedUp(id: "asset-1", signature: "sig"))
    }

    // MARK: - Reconciliation

    @MainActor
    func test_reconcile_forgetsEntriesTheServerNoLongerHas() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("gone"), candidate("kept")]
        source.dataProvider = { _ in Data(repeating: 1, count: 8) }
        // Run 1 uploads both, filling the ledger with their checksums.
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(results: [
            .init(id: "gone", action: "accept"),
            .init(id: "kept", action: "accept"),
        ])
        let ledger = BackupLedger.inMemory()
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )
        await engine.run(settings: settings())
        XCTAssertEqual(ledger.trackedCount(), 2)

        // The server lost "gone" (deleted, purged, restored from an older
        // backup). The weekly pass must forget it — and the run that follows
        // must re-upload it while leaving the other one alone.
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(results: [
            .init(id: "gone", action: "accept"),
            .init(id: "kept", action: "reject", reason: "duplicate"),
        ])
        await engine.reconcileNow()
        XCTAssertEqual(ledger.trackedCount(), 1, "seul l'asset absent du serveur est oublié")

        await engine.run(settings: settings())

        XCTAssertEqual(engine.uploadedCount, 1, "l'asset disparu du serveur est re-uploadé")
        XCTAssertEqual(mock.lastUploadFilename, "gone.jpg")
        XCTAssertEqual(engine.rejectedCount, 1, "celui que le serveur a encore est rejeté")
    }

    /// A run whose reconciliation is not due must not spend a single request on
    /// it — the first chunk of `bulkUploadCheck` in the run is the dedup pass.
    @MainActor
    func test_reconcile_skippedWhenNotDue() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("c1")]
        source.dataProvider = { _ in Data(repeating: 1, count: 8) }
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "c1", action: "accept")]
        )
        let ledger = BackupLedger.inMemory()
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )
        await engine.run(settings: settings())

        // Second run within the interval: the first bulk-check already carries
        // the asset id, i.e. it is the dedup chunk, not a reconciliation one.
        mock.bulkUploadCheckChunks = []
        await engine.run(settings: settings())

        XCTAssertEqual(mock.bulkUploadCheckChunks.flatMap { $0 }.map(\.id), [],
                       "ledger intact → rien à dédupliquer, rien à réconcilier")
    }

    @MainActor
    func test_reconcile_networkErrorDoesNotFailRunNorSetLastError() async {
        let mock = MockImmichClient()
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "a1", signature: "sig", checksum: "sum")
        mock.globalError = APIError.serverError(500, "boom")
        let engine = BackupEngine(
            client: mock, source: MockBackupAssetSource(),
            environment: MockBackupEnvironment(), ledger: ledger
        )

        await engine.reconcileNow()

        XCTAssertNil(engine.lastError, "une erreur réseau sur la passe n'est pas un échec de run")
        XCTAssertTrue(engine.failures.isEmpty)
        XCTAssertNil(ledger.lastReconciliation, "la passe ratée n'est pas horodatée")
        XCTAssertEqual(ledger.trackedCount(), 1, "et rien n'est oublié à l'aveugle")
    }

    @MainActor
    func test_reconcile_chunksAtCheckChunkSize() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.dataProvider = { _ in Data(repeating: 1, count: 8) }
        let ledger = BackupLedger.inMemory()
        for i in 0..<250 {
            ledger.markBackedUp(id: "a\(i)", signature: "sig", checksum: "sum\(i)")
        }
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )
        mock.bulkUploadCheckChunks = []

        await engine.reconcileNow()

        XCTAssertEqual(mock.bulkUploadCheckChunks.count, 3, "100 + 100 + 50")
        XCTAssertEqual(mock.bulkUploadCheckChunks[0].count, 100)
        XCTAssertEqual(mock.bulkUploadCheckChunks[2].count, 50)
    }

    @MainActor
    func test_entriesWithoutChecksumAreNotReconciled() async {
        let url = try? writeLedgerFile(#"{"legacy":"sig"}"#)
        let ledger = BackupLedger(fileURL: url)
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )
        mock.bulkUploadCheckChunks = []

        await engine.reconcileNow()

        XCTAssertTrue(mock.bulkUploadCheckChunks.isEmpty, "aucune entrée à rejouer")
        XCTAssertEqual(ledger.trackedCount(), 1, "et surtout : l'entrée n'est pas oubliée")
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    @MainActor
    func test_reconcile_keepsRejectedEntries() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "trashed", signature: "sig", checksum: "sum")
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(results: [
            .init(id: "trashed", action: "reject", reason: "duplicate", assetId: "remote", isTrashed: true),
        ])
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )

        await engine.reconcileNow()

        XCTAssertEqual(ledger.trackedCount(), 1,
                       "un asset dans la corbeille serveur est TOUJOURS là : ne pas le ré-uploader")
    }

    @MainActor
    func test_reconcile_isSkippedOffline() async {
        let mock = MockImmichClient()
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "a1", signature: "sig", checksum: "sum")
        let env = MockBackupEnvironment()
        env.isOnlineValue = false
        let engine = BackupEngine(
            client: mock, source: MockBackupAssetSource(), environment: env, ledger: ledger
        )

        await engine.reconcileNow()

        XCTAssertEqual(mock.requestCount, 0)
        XCTAssertNil(ledger.lastReconciliation)
    }

    @MainActor
    func test_reconcileNow_stampsLastReconciliation() async {
        let mock = MockImmichClient()
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "a1", signature: "sig", checksum: "sum")
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "a1", action: "reject", reason: "duplicate")]
        )
        let engine = BackupEngine(
            client: mock, source: MockBackupAssetSource(),
            environment: MockBackupEnvironment(), ledger: ledger
        )

        XCTAssertNil(ledger.lastReconciliation)
        await engine.reconcileNow()
        XCTAssertNotNil(ledger.lastReconciliation)
        XCTAssertNotNil(engine.lastReconciliation)
    }

    /// A forgotten asset must be re-uploaded by the *same* run: the scan that
    /// follows the pass has to see it as a candidate.
    @MainActor
    func test_forgottenAssetIsReUploadedInSameRun() async {
        let mock = MockImmichClient()
        let source = MockBackupAssetSource()
        source.candidates = [candidate("a1")]
        source.dataProvider = { _ in Data(repeating: 1, count: 8) }
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "a1", signature: "2024-07-01T00:00:00.000Z", checksum: "sum")
        // The server answers "accept" for the reconciliation and for the dedup
        // pass that follows.
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "a1", action: "accept")]
        )
        let engine = BackupEngine(
            client: mock, source: source, environment: MockBackupEnvironment(), ledger: ledger
        )

        await engine.run(settings: settings())

        XCTAssertEqual(engine.total, 1, "l'asset oublié redevient candidat dans le même run")
        XCTAssertEqual(engine.uploadedCount, 1)
    }

    @MainActor
    func test_resetClearsReconciliationDate() async {
        let mock = MockImmichClient()
        let ledger = BackupLedger.inMemory()
        ledger.markBackedUp(id: "a1", signature: "sig", checksum: "sum")
        mock.bulkUploadCheckResponse = AssetBulkUploadCheckResponse(
            results: [.init(id: "a1", action: "reject", reason: "duplicate")]
        )
        let engine = BackupEngine(
            client: mock, source: MockBackupAssetSource(),
            environment: MockBackupEnvironment(), ledger: ledger
        )
        await engine.reconcileNow()
        XCTAssertNotNil(ledger.lastReconciliation)

        engine.forgetAllBackedUp()

        XCTAssertNil(ledger.lastReconciliation, "un ledger vidé n'a plus de date de vérification")
        XCTAssertEqual(ledger.trackedCount(), 0)
    }
}
