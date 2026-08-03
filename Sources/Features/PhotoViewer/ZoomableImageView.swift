import SwiftUI

/// Photos-grade zoomable image page for the full-screen photo viewer.
///
/// Gesture surface:
/// - **Pinch** (`MagnifyGesture`) zooms in [1, 4], anchored at center.
/// - **Double-tap** toggles 1x ↔ 3x (Photos default zoom).
/// - **Pan** moves the image while zoomed; at 1x it is a no-op so the pager
///   (TabView) owns horizontal drags.
/// - **Single tap** toggles the viewer chrome (parent callback).
///
/// The pan gesture is attached with `.highPriorityGesture` only while zoomed
/// so it wins over the pager; at 1x it degrades to `.simultaneousGesture` (a
/// guarded no-op) so paging stays responsive. Reset-on-page-change is handled
/// by the pager giving each page a stable `.id(asset.id)` — SwiftUI recreates
/// the view (and its `@State`) when the asset changes.
struct ZoomableImageView: View {
    let asset: AssetReactItem
    let baseURL: URL
    let token: String?
    var onSingleTap: () -> Void = {}
    /// Reports the current scale so the parent can gate swipe-to-dismiss.
    var onZoomChange: (CGFloat) -> Void = { _ in }

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    private var isZoomed: Bool { scale > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            // Explicit full frame: GeometryReader aligns its child top-leading,
            // so a content-sized `.fit` image would sit at the top, not centered.
            // The frame fills the page and centers the fitted image in both axes.
            let base = AuthenticatedAsyncImage(
                url: asset.thumbnailURL(base: baseURL, size: .fullsize),
                token: token,
                contentMode: .fit
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = Self.clamp(lastScale * value.magnification, min: minScale, max: maxScale)
                        onZoomChange(scale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.05 {
                            // Photos never rests between 1x and the zoom threshold.
                            withAnimation(PVMotion.snappy) {
                                scale = 1
                                offset = .zero
                            }
                            lastScale = 1
                            lastOffset = .zero
                        }
                        onZoomChange(scale)
                    }
            )

            if isZoomed {
                base
                    .highPriorityGesture(panGesture(size: proxy.size))
                    .onTapGesture(count: 2, perform: toggleZoom)
                    .onTapGesture(perform: onSingleTap)
            } else {
                base
                    .simultaneousGesture(panGesture(size: proxy.size))
                    .onTapGesture(count: 2, perform: toggleZoom)
                    .onTapGesture(perform: onSingleTap)
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }

    // MARK: - Gestures

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard isZoomed else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard isZoomed else { return }
                lastOffset = offset
                withAnimation(PVMotion.snappy) {
                    offset = clampedOffset(for: size)
                }
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(PVMotion.snappy) {
            if isZoomed {
                scale = 1
                offset = .zero
            } else {
                scale = 3
            }
        }
        lastScale = scale
        lastOffset = offset
        onZoomChange(scale)
    }

    // MARK: - Helpers

    /// Clamps the pan so the image never detaches from the viewport edge.
    private func clampedOffset(for size: CGSize) -> CGSize {
        let excessW = max(0, (size.width * scale - size.width) / 2)
        let excessH = max(0, (size.height * scale - size.height) / 2)
        return CGSize(
            width: Self.clamp(offset.width, min: -excessW, max: excessW),
            height: Self.clamp(offset.height, min: -excessH, max: excessH)
        )
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
