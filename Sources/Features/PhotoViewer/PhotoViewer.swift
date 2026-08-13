import SwiftUI
import UIKit

/// Identifiable payload for `.fullScreenCover(item:)` — carries the ordered
/// photo list (the paging source) plus the tapped index.
struct PhotoViewerItem: Identifiable {
    let assets: [AssetReactItem]
    let index: Int
    var id: String { assets.indices.contains(index) ? assets[index].id : UUID().uuidString }
}

/// Pure swipe-decision thresholds for the viewer's gestures — unit-testable,
/// no SwiftUI state:
/// - Swipe down (1x): dismiss the viewer / close the open info panel.
/// - Swipe up (1x): reveal the info panel.
/// Progress is the drag translation as a fraction of the panel height (negative
/// = upward); velocity is the predicted end translation delta.
enum PhotoViewerSwipeDecision {
    static let progressThreshold: CGFloat = 0.25
    static let velocityThreshold: CGFloat = 900

    /// Downward drag past the threshold, or a strong downward flick.
    static func shouldClose(progress: CGFloat, velocity: CGFloat) -> Bool {
        progress > progressThreshold || velocity > velocityThreshold
    }

    /// Upward drag past the threshold, or a strong upward flick.
    static func shouldOpen(progress: CGFloat, velocity: CGFloat) -> Bool {
        progress < -progressThreshold || velocity < -velocityThreshold
    }
}

/// Presents the Photos-style full-screen photo viewer for `assets`, opened at
/// `item.index`. `item` is nilled out to dismiss.
struct PhotoViewerPresentation: ViewModifier {
    @Binding var item: PhotoViewerItem?
    let baseURL: URL
    let token: String?
    var client: any ImmichClient = DependencyContainer.shared.client
    var onToggleFavorite: ((AssetReactItem) -> Void)? = nil
    var onDelete: ((AssetReactItem) -> Void)? = nil
    var onRestore: ((AssetReactItem) -> Void)? = nil
    var onDeletePermanent: ((AssetReactItem) -> Void)? = nil
    var onDataChanged: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $item) { item in
                PhotoViewer(
                    assets: item.assets,
                    index: item.index,
                    baseURL: baseURL,
                    token: token,
                    client: client,
                    onToggleFavorite: onToggleFavorite,
                    onDelete: onDelete,
                    onRestore: onRestore,
                    onDeletePermanent: onDeletePermanent,
                    onDataChanged: onDataChanged
                )
            }
    }
}

extension View {
    /// Attaches the full-screen photo viewer to a grid. Set `item` on tap to
    /// open; nilling it dismisses.
    ///
    /// The viewer is self-sufficient (share / favorite / edit / delete run on
    /// the shared `client`), but per-surface VM callbacks — when provided —
    /// take precedence for favorite/delete/restore so the grid updates in
    /// place. `onDataChanged` fires after self-contained mutations so the
    /// surface can refresh its list.
    func photoViewer(
        item: Binding<PhotoViewerItem?>,
        baseURL: URL,
        token: String?,
        client: any ImmichClient = DependencyContainer.shared.client,
        onToggleFavorite: ((AssetReactItem) -> Void)? = nil,
        onDelete: ((AssetReactItem) -> Void)? = nil,
        onRestore: ((AssetReactItem) -> Void)? = nil,
        onDeletePermanent: ((AssetReactItem) -> Void)? = nil,
        onDataChanged: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PhotoViewerPresentation(
                item: item,
                baseURL: baseURL,
                token: token,
                client: client,
                onToggleFavorite: onToggleFavorite,
                onDelete: onDelete,
                onRestore: onRestore,
                onDeletePermanent: onDeletePermanent,
                onDataChanged: onDataChanged
            )
        )
    }
}

/// Full-screen Photos-style photo viewer (iOS 26 Liquid Glass chrome).
///
/// - Black immersive background; the photo is fetched at `.fullsize` and fits.
/// - Horizontal `TabView` paging over the ordered photo list (swipe to browse).
/// - Per-photo pinch-zoom / double-tap / pan via `ZoomableImageView`.
/// - Top glass bar: back (chevron) · location + date · info.
/// - Filmstrip of the whole collection at native aspect ratio (tap to jump).
/// - Bottom: share · glass favorite/edit capsule · delete.
/// - Swipe-down (at 1x) dismisses; swipe-UP (or the info button) slides the
///   EXIF info panel in from the bottom; single tap toggles the chrome.
struct PhotoViewer: View {
    let baseURL: URL
    let token: String?
    var client: any ImmichClient = DependencyContainer.shared.client
    var onToggleFavorite: ((AssetReactItem) -> Void)? = nil
    var onDelete: ((AssetReactItem) -> Void)? = nil
    var onRestore: ((AssetReactItem) -> Void)? = nil
    var onDeletePermanent: ((AssetReactItem) -> Void)? = nil
    var onDataChanged: (() -> Void)? = nil

    /// Local working copy so a delete can shrink the pager live.
    @State private var localAssets: [AssetReactItem]
    @State private var selectedIndex: Int
    @State private var favoriteIDs: Set<String>
    @State private var showChrome = true
    @State private var isZoomed = false
    @State private var dragOffset: CGSize = .zero
    @State private var pendingDeleteIndex: Int?
    @State private var deleteIsPermanent = false
    @State private var presentEdit = false
    @State private var presentShare = false
    @State private var showInfo = false
    @State private var infoDragOffset: CGFloat = 0
    @State private var infoVM: AssetDetailViewModel?
    @State private var filmstripPosition = ScrollPosition()
    /// Asset ids currently showing their Live Photo video pair instead of the
    /// still — per-page toggle, reset when paging away (Photos behavior).
    @State private var livePlayingIDs: Set<String> = []
    /// Internal slideshow overlay (never a new presentation layer — cover-
    /// inside-cover is a teardown crash, memory 2026-08-05). VM is created on
    /// demand from the top-bar button so the slideshow always starts on the
    /// photo that is on screen.
    @State private var slideshowVM: SlideshowViewModel?

    /// Height of the bottom chrome stack — filmstrip (56) + spacing (8) +
    /// bottom bar (68) + safe-area-inset spacing (16) — used to exclude
    /// bottom-chrome drags from the swipe-up reveal. Home indicator comes
    /// on top via `proxy.safeAreaInsets.bottom`.
    static let bottomChromeHeight: CGFloat = 148

    /// Extra travel for the hidden panel so NOTHING pokes above the screen
    /// edge — covers the panel's top shadow (radius 16 + y-offset 4) plus a
    /// small margin.
    static let panelHiddenSlack: CGFloat = 24

    @Environment(\.dismiss) private var dismissAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        assets: [AssetReactItem],
        index: Int,
        baseURL: URL,
        token: String?,
        client: any ImmichClient = DependencyContainer.shared.client,
        onToggleFavorite: ((AssetReactItem) -> Void)? = nil,
        onDelete: ((AssetReactItem) -> Void)? = nil,
        onRestore: ((AssetReactItem) -> Void)? = nil,
        onDeletePermanent: ((AssetReactItem) -> Void)? = nil,
        onDataChanged: (() -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.onRestore = onRestore
        self.onDeletePermanent = onDeletePermanent
        self.onDataChanged = onDataChanged
        _localAssets = State(initialValue: assets)
        _selectedIndex = State(initialValue: assets.isEmpty ? 0 : min(max(index, 0), assets.count - 1))
        _favoriteIDs = State(initialValue: Set(assets.filter(\.isFavorite).map(\.id)))
    }

    var body: some View {
        GeometryReader { proxy in
            // Panel geometry uses the PHYSICAL screen height (UIKit), NOT the
            // proxy size: inside a fullScreenCover the GeometryReader is
            // inset (~home indicator + Liquid Glass chrome), which made a
            // proxy-based hidden panel peek above the screen edge.
            let screenHeight = UIScreen.main.bounds.height
            let panelHeight = screenHeight * PhotoInfoPanel.heightFactor
            let panelTopY = screenHeight - panelHeight
            ZStack {
                Color.black.ignoresSafeArea()

                if !localAssets.isEmpty {
                    pagerView
                }
            }
            // The chrome RESERVES layout space (not an overlay): the top bar and
            // the filmstrip+bottom bar inset the pager, so the photo fits the box
            // "screen width × height between the top buttons and the filmstrip".
            // The `spacing` gaps the photo from the chrome (full-height portraits
            // never touch the top bar or the filmstrip).
            .safeAreaInset(edge: .top, spacing: PVSpacing.s8) {
                if showChrome, let asset = currentAsset {
                    topBar(asset)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: PVSpacing.s16) {
                if showChrome, let asset = currentAsset {
                    VStack(spacing: PVSpacing.s8) {
                        filmstrip
                        bottomBar(asset)
                    }
                }
            }
            .statusBarHidden(true)
            .simultaneousGesture(
                dismissDrag(
                    screenHeight: screenHeight,
                    safeAreaBottom: proxy.safeAreaInsets.bottom,
                    panelTopY: panelTopY,
                    panelHeight: panelHeight
                )
            )
            .offset(y: dragOffset.height)
            .opacity(1 - dismissProgress)
            .onChange(of: selectedIndex) { _, _ in
                isZoomed = false
                showChrome = true
                // Paging away stops any Live Photo pair — back to stills.
                livePlayingIDs.removeAll()
                withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
                    dragOffset = .zero
                }
                // Info stays open while paging — refetch for the new photo.
                if showInfo || infoDragOffset != 0 {
                    refreshInfo()
                }
            }
            .confirmationDialog(
                deleteIsPermanent ? "Delete Permanently?" : "Delete this photo?",
                isPresented: Binding(
                    get: { pendingDeleteIndex != nil },
                    set: { if !$0 { pendingDeleteIndex = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(deleteIsPermanent ? "Delete Permanently" : "Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteIsPermanent
                     ? "This photo will be permanently removed. Action cannot be undone."
                     : "This removes the photo from your library.")
            }
            .sheet(isPresented: $presentEdit) {
                if let asset = currentAsset {
                    PhotoEditorView(vm: DependencyContainer.shared.makePhotoEditorViewModel(asset: asset))
                }
            }
            .sheet(isPresented: $presentShare) {
                if let asset = currentAsset {
                    PhotoShareSheet(asset: asset, baseURL: baseURL, token: token, client: client)
                        .presentationDetents([.fraction(1.0 / 2.0)])
                        .presentationDragIndicator(.visible)
                }
            }

            // Slide-up EXIF info panel (Photos-style). Positioned in ABSOLUTE
            // screen coordinates (sibling of the chrome ZStack, inside the
            // root GeometryReader) — no safe-area involvement, so a hidden
            // panel (center pushed a full panel height below the screen
            // bottom) can never show a sliver.
            if let asset = currentAsset {
                PhotoInfoPanel(
                    asset: asset,
                    client: client,
                    vm: infoVM,
                    panelHeight: panelHeight,
                    isPresented: showInfo || infoDragOffset != 0,
                    onClose: closeInfo,
                    onSnapBack: snapBackInfo,
                    onDragChange: infoDragChanged
                )
                .frame(width: proxy.size.width, height: panelHeight)
                .position(
                    x: proxy.size.width / 2,
                    y: screenHeight - panelHeight / 2
                        + (showInfo ? 0 : panelHeight + Self.panelHiddenSlack) + infoDragOffset
                )
                .allowsHitTesting(showInfo)
            }

            // Slideshow overlay — INTERNAL layer, topmost. It covers the pager,
            // the chrome and the info panel; no new presentation (cover-inside-
            // cover crash lesson 2026-08-05).
            if let vm = slideshowVM {
                SlideshowView(
                    vm: vm,
                    baseURL: baseURL,
                    token: token,
                    onClose: { slideshowVM = nil }
                )
                .zIndex(10)
            }
        }
    }

    // MARK: - Pager

    private var pager: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(localAssets.enumerated()), id: \.element.id) { i, asset in
                Group {
                    if asset.isVideo {
                        VideoPlayerView(
                            asset: asset,
                            baseURL: baseURL,
                            token: token,
                            controlsVisible: showChrome,
                            onSingleTap: dismissOrToggleChrome
                        )
                    } else if let pairID = asset.livePhotoVideoId, livePlayingIDs.contains(asset.id) {
                        // Live Photo playing its video pair (Photos-style).
                        VideoPlayerView(
                            asset: asset,
                            baseURL: baseURL,
                            token: token,
                            assetID: pairID,
                            controlsVisible: showChrome,
                            onSingleTap: dismissOrToggleChrome,
                            onPlaybackEnded: { livePlayingIDs.remove(asset.id) }
                        )
                    } else {
                        ZStack {
                            ZoomableImageView(
                                asset: asset,
                                baseURL: baseURL,
                                token: token,
                                onSingleTap: dismissOrToggleChrome,
                                onZoomChange: { isZoomed = $0 > 1.01 }
                            )
                            if asset.livePhotoVideoId != nil {
                                livePhotoOverlay(asset)
                            }
                        }
                    }
                }
                .id(asset.id)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Chrome visible → the pager fills the box reserved between the top bar
    /// and the filmstrip. Chrome hidden → full-bleed, centered on the TRUE
    /// screen center (Photos behavior), behind the island / home indicator.
    @ViewBuilder
    private var pagerView: some View {
        if showChrome {
            pager
        } else {
            pager.ignoresSafeArea()
        }
    }

    // MARK: - Top bar (back · location+date glass · info)

    private func topBar(_ asset: AssetReactItem) -> some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s16) {
                Button {
                    dismissAction()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                VStack(spacing: 2) {
                    if let place = placeName(for: asset) {
                        Text(place)
                            .font(.pvSubhead.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                    Text(headerDate(for: asset))
                        .font(.pvCaption)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, PVSpacing.s16)
                .padding(.vertical, PVSpacing.s4)
                .glassEffect(.regular, in: Capsule())

                Spacer()

                Button {
                    presentSlideshow()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Slideshow")
                .disabled(localAssets.count < 2)

                Button {
                    openInfo()
                } label: {
                    Image(systemName: "info")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Details")
            }
        }
        .padding(.horizontal, PVSpacing.s16)
        .padding(.top, PVSpacing.s8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    /// Location label — `city`, else `country`, else nil (Photos hides it).
    private func placeName(for asset: AssetReactItem) -> String? {
        if let city = asset.city, !city.isEmpty { return city }
        if let country = asset.country, !country.isEmpty { return country }
        return nil
    }

    // MARK: - Filmstrip (whole collection, native aspect ratio)

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: PVSpacing.s8) {
                ForEach(Array(localAssets.enumerated()), id: \.element.id) { i, asset in
                    Button {
                        withAnimation(PVMotion.snappy) { selectedIndex = i }
                    } label: {
                        AuthenticatedAsyncImage(
                            url: asset.thumbnailURL(base: baseURL, size: .thumbnail),
                            token: token
                        )
                        .frame(width: filmstripWidth(for: asset), height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous)
                                .strokeBorder(i == selectedIndex ? Color.white : Color.clear, lineWidth: 2)
                        )
                        .opacity(i == selectedIndex ? 1.0 : 0.65)
                        .overlay(alignment: .bottomTrailing) {
                            // Video play + duration badge on strip cells so
                            // videos stay recognizable while browsing.
                            if asset.isVideo {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.fill") // DS-exempt: badge micro-glyph §8.6
                                    if let d = asset.duration, d > 0 {
                                        Text(AssetThumbnailCell.formattedDuration(d)).monospacedDigit()
                                    }
                                }
                                .font(.pvCaption)
                                .foregroundStyle(.white) // DS-exempt: badge contrast on material
                                .padding(.horizontal, PVSpacing.s4)
                                .padding(.vertical, 2) // DS-exempt: badge micro-padding
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                                .padding(3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(i + 1) of \(localAssets.count)")
                    .id(i)
                }
            }
            .padding(.horizontal, PVSpacing.s16)
        }
        .frame(height: 56)
        .scrollPosition($filmstripPosition)
        .onAppear { filmstripPosition.scrollTo(id: selectedIndex) }
        .onChange(of: selectedIndex) { _, new in
            filmstripPosition.scrollTo(id: new)
        }
    }

    /// Keeps each filmstrip cell at the photo's own aspect ratio (height 56pt).
    private func filmstripWidth(for asset: AssetReactItem) -> CGFloat {
        min(max(56 * asset.aspectRatio, 28), 88)
    }

    // MARK: - Bottom bar (share · favorite/edit glass · delete)

    private func bottomBar(_ asset: AssetReactItem) -> some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s16) {
                if !isTrash {
                    Button {
                        presentShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.pvHeadline)
                            .foregroundStyle(Color.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }

                Spacer()

                // Center glass capsule: favorite + edit (or restore in Trash).
                HStack(spacing: PVSpacing.s24) {
                    if isTrash {
                        Button {
                            restore(asset)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.pvHeadline)
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Restore")
                    } else {
                        Button {
                            toggleFavorite(asset)
                        } label: {
                            Image(systemName: favoriteIDs.contains(asset.id) ? "heart.fill" : "heart")
                                .font(.pvTitle)
                                .foregroundStyle(favoriteIDs.contains(asset.id) ? Color.immichError : Color.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(favoriteIDs.contains(asset.id) ? "Unfavorite" : "Favorite")

                        if !asset.isVideo {
                            Button {
                                presentEdit = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.pvHeadline)
                                    .foregroundStyle(Color.white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit")
                        }
                    }
                }
                .padding(.horizontal, PVSpacing.s8)
                .padding(.vertical, PVSpacing.s4)
                .glassEffect(.regular, in: Capsule())

                Spacer()

                Button(role: .destructive) {
                    if isTrash {
                        deleteIsPermanent = true
                    } else {
                        deleteIsPermanent = false
                    }
                    pendingDeleteIndex = selectedIndex
                } label: {
                    Image(systemName: isTrash ? "trash.slash" : "trash")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTrash ? "Delete Permanently" : "Delete")
            }
        }
        .padding(.horizontal, PVSpacing.s16)
        .padding(.vertical, PVSpacing.s8)
        .padding(.bottom, PVSpacing.s12)
    }

    /// Trash context is signalled by a `onRestore` callback being provided —
    /// that surface swaps favorite/edit for restore and soft-delete for
    /// delete-permanently (no share).
    private var isTrash: Bool { onRestore != nil }

    /// Starts the slideshow on the currently visible photo. The VM is created
    /// here (top bar button), never stored while inactive — closing the
    /// overlay nils it out, so the next start begins fresh.
    private func presentSlideshow() {
        let vm = SlideshowViewModel(assets: localAssets, startIndex: selectedIndex)
        vm.start()
        slideshowVM = vm
    }

    // MARK: - Info panel

    /// Opens the EXIF panel — same animated movement as a swipe-up release.
    private func openInfo() {
        refreshInfo()
        withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
            showInfo = true
            infoDragOffset = 0
        }
    }

    private func closeInfo() {
        withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
            showInfo = false
            infoDragOffset = 0
        }
    }

    /// Cancelled close-drag: animate back to fully open.
    private func snapBackInfo() {
        withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
            infoDragOffset = 0
        }
    }

    /// The panel's drag handle follows the finger while the panel is open.
    private func infoDragChanged(_ height: CGFloat) {
        guard showInfo, height > 0 else { return }
        infoDragOffset = height
    }

    /// (Re)creates the detail VM for the CURRENT asset — refetches the EXIF
    /// (getAsset + reverse geocode) when the panel opens and when the user
    /// pages to another photo while it is open. Idempotent per asset: called
    /// on EVERY frame of the upward drag, so a fresh VM (and a second
    /// `loadDetail`) is only spawned when the asset actually changed.
    private func refreshInfo() {
        guard let asset = currentAsset else { return }
        if infoVM?.asset.id == asset.id { return }
        let vm = AssetDetailViewModel(asset: asset, client: client)
        infoVM = vm
        Task { await vm.loadDetail() }
    }

    // MARK: - Actions

    private func toggleChrome() {
        withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
            showChrome.toggle()
        }
    }

    /// Shared page tap action: an open info panel closes first, otherwise the
    /// tap toggles the chrome (image zoom pages and video pages both use it).
    private func dismissOrToggleChrome() {
        if showInfo {
            closeInfo()
        } else {
            toggleChrome()
        }
    }

    /// Photos-style LIVE pill over a Live Photo still — tap plays the video
    /// pair, tap again swaps back to the still.
    private func livePhotoOverlay(_ asset: AssetReactItem) -> some View {
        Button {
            withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
                if livePlayingIDs.contains(asset.id) {
                    livePlayingIDs.remove(asset.id)
                } else {
                    livePlayingIDs.insert(asset.id)
                }
            }
        } label: {
            HStack(spacing: PVSpacing.s4) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10)) // DS-exempt: badge micro-glyph
                Text("LIVE")
                    .font(.pvCaption.weight(.bold))
            }
            .foregroundStyle(Color.white) // DS-exempt: badge contrast on material
            .padding(.horizontal, PVSpacing.s12)
            .padding(.vertical, PVSpacing.s4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play Live Photo")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, PVSpacing.s24)
    }

    /// Favorite — uses the surface VM callback when provided, else self-contained.
    private func toggleFavorite(_ asset: AssetReactItem) {
        let newValue = !favoriteIDs.contains(asset.id)
        if newValue {
            favoriteIDs.insert(asset.id)
        } else {
            favoriteIDs.remove(asset.id)
        }
        if let onToggleFavorite {
            onToggleFavorite(asset)
            return
        }
        Task {
            do {
                _ = try await client.updateAsset(id: asset.id, dto: UpdateAssetDto(isFavorite: newValue))
                onDataChanged?()
            } catch {
                // Revert the optimistic toggle — UI never lies about server state.
                if newValue {
                    favoriteIDs.remove(asset.id)
                } else {
                    favoriteIDs.insert(asset.id)
                }
            }
        }
    }

    /// Restore (Trash) — VM callback when provided, else self-contained.
    private func restore(_ asset: AssetReactItem) {
        if let onRestore {
            onRestore(asset)
        } else {
            Task {
                do {
                    _ = try await client.restoreTrashAssets(ids: [asset.id])
                    onDataChanged?()
                } catch {}
            }
        }
        if let index = localAssets.firstIndex(where: { $0.id == asset.id }) {
            removeAsset(at: index)
        }
    }

    private func confirmDelete() {
        guard let index = pendingDeleteIndex, localAssets.indices.contains(index) else {
            pendingDeleteIndex = nil
            return
        }
        let asset = localAssets[index]
        pendingDeleteIndex = nil
        if deleteIsPermanent {
            if let onDeletePermanent {
                onDeletePermanent(asset)
            } else {
                Task {
                    do {
                        try await client.deleteAssets(ids: [asset.id], force: true)
                        onDataChanged?()
                    } catch {}
                }
            }
        } else {
            if let onDelete {
                onDelete(asset)
            } else {
                Task {
                    do {
                        try await client.deleteAssets(ids: [asset.id], force: false)
                        onDataChanged?()
                    } catch {}
                }
            }
        }
        removeAsset(at: index)
    }

    private func removeAsset(at index: Int) {
        let id = localAssets[index].id
        localAssets.removeAll { $0.id == id }
        favoriteIDs.remove(id)
        showInfo = false
        infoDragOffset = 0
        if localAssets.isEmpty {
            dismissAction()
        } else {
            selectedIndex = min(index, localAssets.count - 1)
            showChrome = true
        }
    }

    // MARK: - Swipe-down dismiss / swipe-up info

    private func dismissDrag(
        screenHeight: CGFloat,
        safeAreaBottom: CGFloat,
        panelTopY: CGFloat,
        panelHeight: CGFloat
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let h = value.translation.height
                let w = value.translation.width
                let verticalDominant = abs(h) > abs(w) * 1.2

                // Panel open: a downward drag STARTING on the photo (above the
                // panel) drags it shut; drags on the panel itself belong to its
                // handle / scroll view and are ignored here.
                if showInfo {
                    guard !isZoomed, h > 0, verticalDominant, value.startLocation.y < panelTopY else {
                        infoDragOffset = 0
                        return
                    }
                    infoDragOffset = h
                    return
                }

                guard !isZoomed, verticalDominant else {
                    dragOffset = .zero
                    infoDragOffset = 0
                    return
                }

                // Upward (1x): reveal the info panel — the panel follows the
                // finger; the viewer itself never moves. The detail VM is
                // created on the FIRST frame of the drag so the EXIF is loaded
                // (or already cached) by the time the panel settles open. Any
                // start point on the photo works — only the bottom chrome
                // (filmstrip + bottom bar) is excluded.
                if h < 0, value.startLocation.y < maxSwipeUpStartY(screenHeight: screenHeight, safeAreaBottom: safeAreaBottom) {
                    refreshInfo()
                    infoDragOffset = h
                    dragOffset = .zero
                    return
                }

                // Downward (1x): slide the whole viewer out (dismiss).
                guard h > 0 else {
                    dragOffset = .zero
                    return
                }
                dragOffset = CGSize(width: 0, height: h)
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height

                if showInfo {
                    let progress = infoDragOffset / panelHeight
                    if PhotoViewerSwipeDecision.shouldClose(progress: progress, velocity: velocity) {
                        closeInfo()
                    } else {
                        snapBackInfo()
                    }
                    return
                }

                guard !isZoomed else {
                    dragOffset = .zero
                    return
                }

                // Upward drag → open the panel once past the threshold.
                if infoDragOffset != 0 {
                    let progress = infoDragOffset / panelHeight
                    if PhotoViewerSwipeDecision.shouldOpen(progress: progress, velocity: velocity) {
                        openInfo()
                    } else {
                        snapBackInfo()
                    }
                    return
                }

                let progress = dismissProgress
                if PhotoViewerSwipeDecision.shouldClose(progress: progress, velocity: velocity) {
                    dismissAction()
                } else {
                    withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    /// The asset backing the sheets/filmstrip; nil when the pager is empty or
    /// the index is out of bounds (deleted the last photo).
    private var currentAsset: AssetReactItem? {
        guard localAssets.indices.contains(selectedIndex) else { return nil }
        return localAssets[selectedIndex]
    }

    private var dismissProgress: CGFloat {
        min(max(dragOffset.height / 300, 0), 1)
    }

    /// Highest `startLocation.y` allowed for the swipe-up reveal. With the
    /// chrome shown the bottom `bottomChromeHeight` + home indicator are
    /// excluded (they host the filmstrip / bottom bar); full-bleed (chrome
    /// hidden) any start point works.
    private func maxSwipeUpStartY(screenHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        showChrome
            ? screenHeight - Self.bottomChromeHeight - safeAreaBottom
            : screenHeight
    }

    // MARK: - Helpers

    /// Long-form localized date for the tapped photo ("July 29, 2024").
    private func headerDate(for asset: AssetReactItem) -> String {
        LongDateFormatter.format(isoPrefix: asset.fileCreatedAt)
    }
}

// MARK: - Share sheet

/// Bottom sheet for the viewer's share button (⅓ screen, Photos-style):
/// - Header: native iOS share (left) · "Partager" title · close (right).
/// - "Share with other users": create a new shared album with selected users,
///   or add the photo to an existing shared album.
/// - "Public link": an INDIVIDUAL shared link with permission toggles + copy.
private struct PhotoShareSheet: View {
    let asset: AssetReactItem
    let baseURL: URL
    let token: String?
    let client: any ImmichClient

    @Environment(\.dismiss) private var dismiss
    @State private var vm: PhotoShareViewModel?
    @State private var didCopyLink = false

    var body: some View {
        VStack(spacing: PVSpacing.s0) {
            header
            if let vm {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let new = PhotoShareViewModel(asset: asset, client: client, baseURL: baseURL)
            vm = new
            await new.load()
        }
        .sensoryFeedback(.success, trigger: vm?.lastCreatedAlbumId)
        .sensoryFeedback(.success, trigger: vm?.lastAddedAlbumId)
    }

    private var header: some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s16) {
                Button {
                    Task { await presentNativeShare() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.immichPrimary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")

                Spacer()

                Text("Partager")
                    .font(.pvHeadline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.immichPrimary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, PVSpacing.s16)
        .padding(.vertical, PVSpacing.s8)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func content(_ vm: PhotoShareViewModel) -> some View {
        @Bindable var vm = vm
        List {
            Section {
                TextField("Album name", text: $vm.albumName)
                    .textInputAutocapitalization(.words)

                if vm.users.isEmpty {
                    if vm.isBusy {
                        HStack(spacing: PVSpacing.s8) {
                            ProgressView()
                            Text("Loading users…")
                                .font(.pvCaption)
                                .foregroundStyle(Color.textSecondaryPV)
                        }
                    } else {
                        Text(vm.errorMessage ?? "No users available on this instance.")
                            .font(.pvCaption)
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                } else {
                    ForEach(vm.users, id: \.id) { user in
                        Button {
                            vm.toggleUser(user.id)
                        } label: {
                            HStack(spacing: PVSpacing.s12) {
                                UserAvatarCircle(user: user)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .foregroundStyle(Color.textPrimaryPV)
                                    Text(user.email)
                                        .font(.pvCaption)
                                        .foregroundStyle(Color.textSecondaryPV)
                                }
                                Spacer()
                                Image(systemName: vm.selectedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(vm.selectedUserIds.contains(user.id) ? Color.immichPrimary : Color.textSecondaryPV)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    Task { await vm.createSharedAlbum() }
                } label: {
                    Label("Create shared album", systemImage: "square.stack.badge.plus")
                }
                .disabled(vm.isBusy || vm.selectedUserIds.isEmpty || vm.albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Share with other users")
            }

            Section {
                if vm.sharedAlbums.isEmpty {
                    Text("No shared albums yet. Create one above.")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                } else {
                    ForEach(vm.sharedAlbums, id: \.id) { album in
                        Button {
                            Task { await vm.addToAlbum(id: album.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.albumName)
                                        .foregroundStyle(Color.textPrimaryPV)
                                    Text("\(album.assetCount) items")
                                        .font(.pvCaption)
                                        .foregroundStyle(Color.textSecondaryPV)
                                }
                                Spacer()
                                if vm.lastAddedAlbumId == album.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.immichSuccess)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Add to a shared album")
            }

            Section("Public link") {
                Toggle("Allow download", isOn: $vm.allowDownload)
                Toggle("Show metadata", isOn: $vm.showMetadata)
                if let url = vm.linkURL {
                    VStack(alignment: .leading, spacing: PVSpacing.s8) {
                        Text(url)
                            .font(.pvCaption).monospacedDigit()
                            .foregroundStyle(Color.textSecondaryPV)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            UIPasteboard.general.string = url
                            didCopyLink = true
                        } label: {
                            Label(didCopyLink ? "Copied" : "Copy link",
                                  systemImage: didCopyLink ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        Task { await vm.createPublicLink() }
                    } label: {
                        Label("Create public link", systemImage: "link")
                    }
                    .disabled(vm.isBusy)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Downloads the `.fullsize` image and shares it via the system sheet
    /// (UIActivityViewController). The sheet gets a real FILE URL — not a bare
    /// `UIImage` — so it shows the preview (QuickLook), the original base name
    /// and the file size. The extension comes from the ACTUAL downloaded bytes
    /// (fullsize is often transcoded, e.g. HEIC → JPEG), so the preview matches.
    @MainActor
    private func presentNativeShare() async {
        // Prefer the server-side original base name for a rich share sheet.
        var originalName: String?
        var originalMime: String?
        do {
            let detail = try await client.getAsset(id: asset.id)
            originalName = detail.originalFileName
            originalMime = detail.originalMimeType
        } catch {}

        let url = asset.thumbnailURL(base: baseURL, size: .fullsize)
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
            guard !data.isEmpty else { return }

            // The bytes actually being shared win for the extension (preview
            // accuracy); fall back to the original mime, then jpg.
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            let ext = Self.fileExtension(forMime: contentType ?? originalMime)
            let base = Self.shareFileBaseName(
                originalName: originalName,
                datePrefix: String(asset.fileCreatedAt.prefix(10))
            )
            let fileURL = try Self.writeTempFile(data: data, name: "\(base).\(ext)")
            ActivityPresenter.present(items: [fileURL]) {
                // Remove the whole unique temp directory.
                try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            }
        } catch {}
    }

    /// The shared file's base name (no extension): the server's original file
    /// name stripped of its extension, else a readable date-based fallback.
    private static func shareFileBaseName(originalName: String?, datePrefix: String) -> String {
        if let originalName, !originalName.isEmpty {
            let base = (originalName as NSString).deletingPathExtension
            return base.isEmpty ? originalName : base
        }
        return "Photo-\(datePrefix)"
    }

    /// Maps a MIME type (or falls back to `jpg`) to a file extension so the
    /// system resolves the correct UTI for the QuickLook preview.
    private static func fileExtension(forMime mime: String?) -> String {
        guard let mime else { return "jpg" }
        switch mime.lowercased() {
        case let m where m.contains("png"): return "png"
        case let m where m.contains("webp"): return "webp"
        case let m where m.contains("heic"), let m where m.contains("heif"): return "heic"
        case let m where m.contains("gif"): return "gif"
        case let m where m.contains("avif"): return "avif"
        default: return "jpg"
        }
    }

    /// Writes the image bytes into a UNIQUE temp directory so the shared
    /// file's basename is the real name — no `immich-share-UUID-` prefix
    /// pollutes the filename the share sheet displays.
    private static func writeTempFile(data: Data, name: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

// MARK: - System share presenter

/// Presents `UIActivityViewController` from the top-most presented controller.
@MainActor
private enum ActivityPresenter {
    static func present(items: [Any], completion: (() -> Void)? = nil) {
        guard let top = Self.topViewController() else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = top.view
        if let completion {
            activity.completionWithItemsHandler = { _, _, _, _ in completion() }
        }
        top.present(activity, animated: true)
    }

    private static func topViewController(from base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        if let presented = base?.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = base as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        return base
    }
}

#if DEBUG
// Standalone preview — handy for iterating on the viewer chrome in Xcode.
#Preview("Photo Viewer") {
    PhotoViewer(
        assets: [
            AssetReactItem(id: "p1", ownerId: "o", ratio: 0.75, isFavorite: false, visibility: "timeline", isTrashed: false, isImage: true, thumbhash: nil, createdAt: "2024-07-29T10:00:00.000Z", fileCreatedAt: "2024-07-29T10:00:00.000Z", localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil, city: "Paris", country: "France", latitude: nil, longitude: nil),
            AssetReactItem(id: "p2", ownerId: "o", ratio: 1.5, isFavorite: true, visibility: "timeline", isTrashed: false, isImage: true, thumbhash: nil, createdAt: "2024-07-30T10:00:00.000Z", fileCreatedAt: "2024-07-30T10:00:00.000Z", localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil, city: nil, country: "France", latitude: nil, longitude: nil)
        ],
        index: 0,
        baseURL: URL(string: "https://example.com")!,
        token: nil
    )
}
#endif
