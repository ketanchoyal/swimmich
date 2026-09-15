import XCTest
@testable import ImmichSwiftUI

/// The download queue (gap G10): what the floating panel and the info screen
/// project, and the two server paths behind it (one asset → `/original`,
/// several → `download/info` **then** `download/archive`).
@MainActor
final class DownloadQueueViewModelTests: XCTestCase {

    private var client: MockImmichClient!
    private var transport: FakeDownloadTransport!
    private var vm: DownloadQueueViewModel!

    override func setUp() {
        super.setUp()
        client = MockImmichClient()
        transport = FakeDownloadTransport()
        vm = DownloadQueueViewModel(client: client, transport: transport)
    }

    override func tearDown() {
        // The queue writes to the real `Documents/Downloads` (that is the
        // point of it); the test host's copy is left as it was found.
        for url in vm.items.compactMap(\.destinationURL) {
            try? FileManager.default.removeItem(at: url)
        }
        vm = nil
        transport = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAsset(id: String) -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 0.75, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: true, thumbhash: nil,
            createdAt: "2024-07-01T10:00:00.000Z", fileCreatedAt: "2024-07-01T10:00:00.000Z",
            localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil, stack: []
        )
    }

    private func stubAsset(id: String, name: String, size: Int? = nil, mime: String? = nil) {
        client.getAssetResponse[id] = AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T10:00:00.000Z",
            duration: nil, hasMetadata: true, width: 100, height: 100,
            createdAt: "2024-07-01T10:00:00.000Z", ownerId: "owner", originalPath: "/\(name)",
            originalFileName: name, fileCreatedAt: "2024-07-01T10:00:00.000Z",
            fileModifiedAt: "2024-07-01T10:00:00.000Z", updatedAt: "2024-07-01T10:00:00.000Z",
            isFavorite: false, isArchived: false, isTrashed: false, isOffline: false,
            visibility: "timeline", checksum: "abc", isEdited: false,
            originalMimeType: mime, exifInfo: size.map { ExifResponseDto(fileSizeInByte: $0) }
        )
    }

    /// Lets one of the queue's own tasks reach the transport — `enqueue` starts
    /// each row in a `Task`, so nothing is in flight until this yields.
    private func drain(_ transport: FakeDownloadTransport, requests: Int = 1) async {
        for _ in 0..<200 where transport.requestCount < requests {
            await Task.yield()
        }
    }

    /// Runs the queue to a standstill (every row terminal).
    private func settle() async {
        for _ in 0..<500 where vm.isActive {
            await Task.yield()
        }
    }

    // MARK: - One asset

    func test_singleAsset_runsQueuedThenCompleted_andProgressReachesOne() async {
        stubAsset(id: "a", name: "IMG_0421.HEIC", size: 4096)
        transport.progressSteps = [(1024, 4096), (4096, 4096)]

        await vm.enqueue(asset: makeAsset(id: "a"))
        XCTAssertEqual(vm.status(for: "a"), .queued)
        XCTAssertTrue(vm.isPanelVisible)

        await settle()
        XCTAssertEqual(vm.status(for: "a"), .completed)
        XCTAssertEqual(vm.progress(for: "a"), 1)
        XCTAssertEqual(vm.items.first?.destinationURL?.lastPathComponent, "IMG_0421.HEIC")
    }

    func test_oneRowFailing_doesNotStopTheOthers() async {
        stubAsset(id: "bad", name: "bad.jpg")
        stubAsset(id: "good", name: "good.jpg")
        transport.failures = ["/bad/original": APIError.serverError(500, "boom")]

        await vm.enqueue(asset: makeAsset(id: "bad"))
        await vm.enqueue(asset: makeAsset(id: "good"))
        await settle()

        XCTAssertEqual(vm.status(for: "bad"), .failed)
        XCTAssertNotNil(vm.items.first { $0.id == "bad" }?.errorMessage)
        XCTAssertEqual(vm.status(for: "good"), .completed)
    }

    /// A 404 writes its error body to disk like any other response: reporting
    /// `.completed` over it is the one outcome this feature must never produce.
    func test_errorStatus_failsTheRow_insteadOfReportingItDone() async {
        stubAsset(id: "a", name: "a.jpg")
        transport.statusCode = 404

        await vm.enqueue(asset: makeAsset(id: "a"))
        await settle()

        XCTAssertEqual(vm.status(for: "a"), .failed)
        XCTAssertEqual(vm.completedCount, 0)
        XCTAssertNotNil(vm.items.first?.errorMessage)
        XCTAssertNil(vm.items.first?.destinationURL)
    }

    func test_finishedFile_landsInDocumentsDownloads_withTheServerName() async throws {
        stubAsset(id: "a", name: "IMG_0421.HEIC", size: 4096)
        transport.payload = Data("original-bytes".utf8)

        await vm.enqueue(asset: makeAsset(id: "a"))
        await settle()

        let item = try XCTUnwrap(vm.items.first)
        let url = try XCTUnwrap(item.destinationURL)
        XCTAssertTrue(
            url.path.hasSuffix("/Documents/Downloads/IMG_0421.HEIC"),
            "a download lands in Documents/Downloads under the server's name, got \(url.path)"
        )
        XCTAssertEqual(try Data(contentsOf: url), Data("original-bytes".utf8))
        XCTAssertEqual(item.receivedBytes, 4096)
    }

    func test_sameServerNameTwice_doesNotOverwriteTheFirstFile() async throws {
        stubAsset(id: "a", name: "IMG_0421.HEIC")
        stubAsset(id: "b", name: "IMG_0421.HEIC")

        transport.payload = Data("first".utf8)
        await vm.enqueue(asset: makeAsset(id: "a"))
        await settle()
        transport.payload = Data("second".utf8)
        await vm.enqueue(asset: makeAsset(id: "b"))
        await settle()

        let first = try XCTUnwrap(vm.items.first { $0.id == "a" }?.destinationURL)
        let second = try XCTUnwrap(vm.items.first { $0.id == "b" }?.destinationURL)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
    }

    // MARK: - A batch

    func test_batch_announcesTheBatchBeforeAskingForTheArchive() async {
        let archives = [DownloadInfoResponse.Archive(assetIds: ["a", "b"], size: 12_000)]
        client.downloadInfoResponse = DownloadInfoResponse(totalSize: 12_000, archives: archives)

        await vm.enqueue(assets: [makeAsset(id: "a"), makeAsset(id: "b")])
        XCTAssertEqual(client.downloadCallOrder, ["info"], "info must come first")
        XCTAssertEqual(client.lastDownloadInfoAssetIds, ["a", "b"])
        XCTAssertNil(client.lastDownloadInfoAlbumId)

        await settle()
        XCTAssertEqual(client.downloadCallOrder, ["info", "archive"])
        XCTAssertEqual(client.lastArchiveAssetIds, ["a", "b"])
        XCTAssertEqual(client.lastArchiveEdited, false)
        XCTAssertEqual(client.lastArchiveName, vm.items.first?.fileName)
    }

    func test_batch_isOneRowPerArchive_theServerSplits() async {
        client.downloadInfoResponse = DownloadInfoResponse(
            totalSize: 10_000,
            archives: [
                DownloadInfoResponse.Archive(assetIds: ["a"], size: 4000),
                DownloadInfoResponse.Archive(assetIds: ["b"], size: 6000)
            ]
        )

        await vm.enqueue(assets: [makeAsset(id: "a"), makeAsset(id: "b")])
        await settle()

        XCTAssertEqual(vm.totalCount, 2)
        XCTAssertEqual(Set(vm.items.map(\.fileName)).count, 2, "two archives must not share a name")
        XCTAssertTrue(vm.items.allSatisfy(\.isArchive))
        XCTAssertEqual(
            vm.formattedAggregateSize,
            ByteCountFormatter.string(fromByteCount: 10_000, countStyle: .file)
        )
        XCTAssertEqual(vm.aggregateProgress, 1)
    }

    func test_batchTheServerRefuses_reportsAnError_withoutQueueingRows() async {
        client.downloadInfoError = APIError.serverError(500, "nope")

        await vm.enqueue(assets: [makeAsset(id: "a"), makeAsset(id: "b")])

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.isPanelVisible)
    }

    // MARK: - Row actions

    func test_cancel_parksAnInFlightRow_withoutAnError() async {
        stubAsset(id: "a", name: "a.jpg")
        transport.stalls = true

        await vm.enqueue(asset: makeAsset(id: "a"))
        await drain(transport)
        XCTAssertEqual(vm.status(for: "a"), .running)

        vm.cancel(assetId: "a")

        XCTAssertEqual(vm.status(for: "a"), .cancelled)
        XCTAssertNil(vm.items.first?.errorMessage)
        XCTAssertFalse(vm.isPanelVisible)
    }

    func test_retry_rerunsAFailedRow() async {
        stubAsset(id: "a", name: "a.jpg")
        transport.failures = ["/original": APIError.serverError(500, nil)]

        await vm.enqueue(asset: makeAsset(id: "a"))
        await settle()
        XCTAssertEqual(vm.status(for: "a"), .failed)

        transport.failures = [:]
        vm.retry(assetId: "a")
        await settle()

        XCTAssertEqual(vm.status(for: "a"), .completed)
        XCTAssertNil(vm.items.first?.errorMessage)
        XCTAssertEqual(transport.requestCount, 2)
    }

    func test_clearCompleted_dropsFinishedRows_andKeepsFailedOnes() async {
        stubAsset(id: "done", name: "done.jpg")
        stubAsset(id: "broken", name: "broken.jpg")
        transport.failures = ["/broken/original": APIError.serverError(500, nil)]

        await vm.enqueue(asset: makeAsset(id: "broken"))
        await vm.enqueue(asset: makeAsset(id: "done"))
        await settle()

        vm.clearCompleted()

        XCTAssertEqual(vm.items.map(\.id), ["broken"])
        XCTAssertEqual(vm.failedCount, 1)
    }

    /// A cancelled row has no action of its own, so it must not be stranded:
    /// upstream drops a cancelled task from its map outright.
    func test_clearCompleted_dropsCancelledRows_too() async {
        stubAsset(id: "a", name: "a.jpg")
        transport.stalls = true

        await vm.enqueue(asset: makeAsset(id: "a"))
        await drain(transport)
        vm.cancel(assetId: "a")
        XCTAssertEqual(vm.cancelledCount, 1)

        vm.clearCompleted()

        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.isPanelVisible)
    }

    func test_isPanelVisible_followsTheQueue_andTheRowSurvivesIt() async {
        stubAsset(id: "a", name: "a.jpg")
        XCTAssertFalse(vm.isPanelVisible)

        await vm.enqueue(asset: makeAsset(id: "a"))
        XCTAssertTrue(vm.isPanelVisible, "a queued row is what raises the panel")

        await settle()
        XCTAssertFalse(vm.isPanelVisible)
        XCTAssertEqual(vm.totalCount, 1, "the finished row is still listed until cleared")
    }

    /// The same asset asked for twice raises the row that is already there —
    /// a second copy of the same file is never queued.
    func test_enqueueingTheSameAssetTwice_keepsOneRow() async {
        stubAsset(id: "a", name: "a.jpg")

        await vm.enqueue(asset: makeAsset(id: "a"))
        await vm.enqueue(asset: makeAsset(id: "a"))
        await settle()

        XCTAssertEqual(vm.totalCount, 1)
        XCTAssertEqual(vm.completedCount, 1)
    }
}

/// Transport double for the queue.
///
/// `MockFileDownloadTransport` (the offline cache's double) scripts ONE
/// payload for every download; a queue needs per-row outcomes — one row
/// failing while its neighbour finishes — and a gate that holds a row in
/// flight while the test cancels it. `URLProtocol` cannot stand in either: it
/// delivers its payload in one shot and never invokes the download delegate.
private final class FakeDownloadTransport: FileDownloadTransport, @unchecked Sendable {
    /// Errors keyed by a fragment of the request URL, so a test can fail one
    /// row whatever order the queue runs its rows in.
    var failures: [String: Error] = [:]
    /// When true every download suspends until the task is cancelled.
    var stalls = false
    /// Payload written by the next download.
    var payload = Data("original".utf8)
    var statusCode: Int? = 200
    /// Progress pairs replayed before the download returns.
    var progressSteps: [(Int64, Int64)] = []

    private let lock = NSLock()
    private var gated = false
    private var stallContinuation: CheckedContinuation<Void, Error>?
    private var count = 0
    private var seen: [URLRequest] = []

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    func download(
        _ request: URLRequest,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> DownloadedFile {
        lock.lock()
        count += 1
        seen.append(request)
        let stalls = self.stalls
        let failure = failures.first { request.url?.absoluteString.contains($0.key) == true }?.value
        let payload = self.payload
        let status = self.statusCode
        let steps = self.progressSteps
        lock.unlock()

        if let failure { throw failure }
        if stalls { try await waitForRelease() }

        for step in steps {
            onProgress(step.0, step.1)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-download-\(UUID().uuidString)")
        try payload.write(to: url)
        return DownloadedFile(url: url, statusCode: status, contentType: "image/jpeg")
    }

    /// Suspends until cancelled — the window in which a test stops a row.
    private func waitForRelease() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if gated {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                stallContinuation = continuation
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            gated = true
            let continuation = stallContinuation
            stallContinuation = nil
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }
}
