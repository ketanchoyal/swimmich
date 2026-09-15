import XCTest
@testable import ImmichSwiftUI

/// ocr-text (gap #8): the overlay's state machine and the geometry that puts
/// the boxes on the photo.
@MainActor
final class OcrOverlayViewModelTests: XCTestCase {

    private func makeBox(
        id: String,
        text: String,
        textScore: Double = 0.9,
        y1: Double = 0.1
    ) -> AssetOcrResponseDto {
        AssetOcrResponseDto(
            id: id, assetId: "asset-1", text: text, boxScore: 0.8, textScore: textScore,
            x1: 0.1, x2: 0.5, x3: 0.5, x4: 0.1,
            y1: y1, y2: y1, y3: y1 + 0.1, y4: y1 + 0.1
        )
    }

    // MARK: - Loading

    func test_load_fetchesBoxesForItsAsset() async {
        let mock = MockImmichClient()
        mock.ocrByAssetId["asset-1"] = [makeBox(id: "b1", text: "Receipt")]
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertEqual(mock.lastGetAssetOcrId, "asset-1")
        XCTAssertEqual(vm.boxes.map(\.text), ["Receipt"])
        XCTAssertTrue(vm.didLoad)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    /// The server's array order is unspecified: the overlay reads the boxes
    /// most-confident-first, then top-to-bottom on the image.
    func test_load_ordersBoxesForReading() async {
        let mock = MockImmichClient()
        mock.ocrByAssetId["asset-1"] = [
            makeBox(id: "low", text: "low", textScore: 0.4, y1: 0.1),
            makeBox(id: "second", text: "second", textScore: 0.9, y1: 0.6),
            makeBox(id: "first", text: "first", textScore: 0.9, y1: 0.2),
        ]
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertEqual(vm.boxes.map(\.id), ["first", "second", "low"])
    }

    /// An empty answer means "no text on this photo" — never an error.
    func test_load_emptyResult_isNotAnError() async {
        let mock = MockImmichClient()
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertTrue(vm.boxes.isEmpty)
        XCTAssertTrue(vm.didLoad)
        XCTAssertNil(vm.errorMessage)
    }

    /// The boxes are cached for the lifetime of the instance — one request per
    /// asset, whatever the number of toggles.
    func test_load_secondCallDoesNotRefetch() async {
        let mock = MockImmichClient()
        mock.ocrByAssetId["asset-1"] = [makeBox(id: "b1", text: "Receipt")]
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()
        await vm.load()

        XCTAssertEqual(mock.requestCount, 1)
    }

    // MARK: - Failures

    func test_load_error_exposesMessage() async {
        let mock = MockImmichClient()
        struct Boom: Error {}
        mock.ocrError = Boom()
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertEqual(vm.errorMessage, localizedString("Detected text unavailable"))
        XCTAssertTrue(vm.boxes.isEmpty)
        XCTAssertFalse(vm.didLoad, "a failed load stays retryable")
    }

    /// Recovery path: re-enabling the toggle retries the failed fetch.
    func test_load_retriesAfterFailure() async {
        let mock = MockImmichClient()
        struct Boom: Error {}
        mock.ocrError = Boom()
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)
        await vm.load()

        mock.ocrError = nil
        mock.ocrByAssetId["asset-1"] = [makeBox(id: "b1", text: "Receipt")]
        await vm.load()

        XCTAssertEqual(mock.requestCount, 2)
        XCTAssertEqual(vm.boxes.map(\.text), ["Receipt"])
        XCTAssertNil(vm.errorMessage)
    }

    /// Paging away mid-fetch cancels the request — a normal outcome that must
    /// stay invisible.
    func test_load_cancellation_isSwallowed() async {
        let mock = MockImmichClient()
        mock.ocrError = CancellationError()
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.didLoad)
    }

    func test_load_cancelledURL_isSwallowed() async {
        let mock = MockImmichClient()
        mock.ocrError = URLError(.cancelled)
        let vm = OcrOverlayViewModel(assetId: "asset-1", client: mock)

        await vm.load()

        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Geometry

    /// The single mapping formula: normalized (0–1) → fitted image rect →
    /// viewport, with zoom around the viewport center and then the pan.
    func test_screenPoint_mapsThroughFitAndZoom() {
        let imageRect = CGRect(x: 50, y: 0, width: 100, height: 100)
        let viewport = CGSize(width: 200, height: 100)

        // 1x, no pan: the normalized point lands on the fitted image.
        XCTAssertEqual(
            OcrOverlayView.screenPoint(
                CGPoint(x: 0, y: 0), imageRect: imageRect,
                scale: 1, offset: .zero, viewport: viewport
            ),
            CGPoint(x: 50, y: 0)
        )
        XCTAssertEqual(
            OcrOverlayView.screenPoint(
                CGPoint(x: 0.5, y: 0.5), imageRect: imageRect,
                scale: 1, offset: .zero, viewport: viewport
            ),
            CGPoint(x: 100, y: 50),
            "the image center keeps matching the viewport center"
        )

        // 2x around the center, then pan — mirrors `.scaleEffect` + `.offset`.
        XCTAssertEqual(
            OcrOverlayView.screenPoint(
                CGPoint(x: 0, y: 0), imageRect: imageRect,
                scale: 2, offset: CGSize(width: 10, height: -20), viewport: viewport
            ),
            CGPoint(x: 10, y: -70)
        )
    }

    /// A tilted box is drawn as a quadrilateral: a point of the axis-aligned
    /// bounding box that sits outside the tilted shape must not be covered.
    func test_quadPath_keepsTilt() {
        let quad = OcrQuad(
            topLeft: CGPoint(x: 0.2, y: 0.2),
            topRight: CGPoint(x: 0.8, y: 0.3),
            bottomRight: CGPoint(x: 0.8, y: 0.4),
            bottomLeft: CGPoint(x: 0.2, y: 0.3)
        )
        let path = quad.path(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: 1, offset: .zero, viewport: CGSize(width: 100, height: 100)
        )

        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 30)), "the centroid is inside the box")
        XCTAssertFalse(
            path.contains(CGPoint(x: 25, y: 38)),
            "a bbox would cover this point; the tilted quad must not"
        )
    }

    /// `isConfident` is the label threshold, not a data filter.
    func test_isConfident_threshold() {
        XCTAssertTrue(makeBox(id: "a", text: "a", textScore: 0.5).isConfident)
        XCTAssertFalse(makeBox(id: "b", text: "b", textScore: 0.49).isConfident)
    }
}
