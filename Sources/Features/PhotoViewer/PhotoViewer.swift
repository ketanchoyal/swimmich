import SwiftUI
import UIKit
import MapKit

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
    var onArchive: ((AssetReactItem) -> Void)? = nil
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
                    onArchive: onArchive,
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
        onArchive: ((AssetReactItem) -> Void)? = nil,
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
                onArchive: onArchive,
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
    var onArchive: ((AssetReactItem) -> Void)? = nil
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
        onArchive: ((AssetReactItem) -> Void)? = nil,
        onRestore: ((AssetReactItem) -> Void)? = nil,
        onDeletePermanent: ((AssetReactItem) -> Void)? = nil,
        onDataChanged: (() -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.onArchive = onArchive
        self.onRestore = onRestore
        self.onDeletePermanent = onDeletePermanent
        self.onDataChanged = onDataChanged
        _localAssets = State(initialValue: assets)
        _selectedIndex = State(initialValue: assets.isEmpty ? 0 : min(max(index, 0), assets.count - 1))
        _favoriteIDs = State(initialValue: Set(assets.filter(\.isFavorite).map(\.id)))
    }

    var body: some View {
        GeometryReader { proxy in
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
                    screenHeight: UIScreen.main.bounds.height,
                    safeAreaBottom: proxy.safeAreaInsets.bottom
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
                if showInfo {
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

            // EXIF info bottom sheet (native Liquid Glass, like tags/faces).
            .sheet(isPresented: $showInfo) {
                if let asset = currentAsset {
                    PhotoInfoPanel(
                        asset: asset,
                        client: client,
                        vm: infoVM,
                        baseURL: baseURL,
                        token: token,
                        onClose: { showInfo = false },
                        onOpenInMaps: openInMaps
                    )
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
                }
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
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: Capsule())

                Spacer()

                Button {
                    presentSlideshow()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
                            .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: Capsule())

                Spacer()

                if !isTrash {
                    Button {
                        archive(asset)
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.pvHeadline)
                            .foregroundStyle(Color.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Archive")
                }

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
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
        // No `vm.start()` here — `SlideshowView.onAppear` starts the loop,
        // avoiding a double start (and the VM is created fresh each time).
        slideshowVM = vm
    }

    // MARK: - Info panel

    /// Opens the EXIF info bottom sheet — refreshes the detail VM then presents.
    private func openInfo() {
        refreshInfo()
        showInfo = true
    }

    private func closeInfo() {
        showInfo = false
    }

    /// (Re)creates the detail VM for the CURRENT asset — refetches the EXIF
    /// (getAsset + reverse geocode + faces) when the sheet opens and when the
    /// user pages to another photo while it is open. Idempotent per asset.
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

    /// map-extras: launch Apple Maps at the photo's coordinates, named after
    /// its place label when one is known. Handed to the info panel's
    /// where-card action row.
    private func openInMaps(_ latitude: Double, _ longitude: Double) {
        let cityCountry = [currentAsset?.city, currentAsset?.country].compactMap { $0 }.joined(separator: ", ")
        let item = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        )
        item.name = infoVM?.placeName ?? (cityCountry.isEmpty ? nil : cityCountry)
        item.openInMaps()
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

    /// Archive — surface VM callback when provided, else self-contained
    /// (bulk visibility "archive", mirrors the delete self-contained path).
    /// No confirmation: archiving is reversible.
    private func archive(_ asset: AssetReactItem) {
        if let onArchive {
            onArchive(asset)
            return
        }
        Task {
            do {
                try await client.bulkUpdateAssets(dto: AssetBulkUpdateDto(ids: [asset.id], visibility: .archive))
                onDataChanged?()
            } catch {}
        }
        if let index = localAssets.firstIndex(where: { $0.id == asset.id }) {
            removeAsset(at: index)
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
        safeAreaBottom: CGFloat
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard slideshowVM == nil else { dragOffset = .zero; return }
                let h = value.translation.height
                let w = value.translation.width
                let verticalDominant = abs(h) > abs(w) * 1.2

                guard !isZoomed, verticalDominant else {
                    dragOffset = .zero
                    return
                }

                // Only a downward drag slides the viewer; upward is a candidate
                // for the info sheet and never moves the viewer.
                guard h > 0 else {
                    dragOffset = .zero
                    return
                }
                dragOffset = CGSize(width: 0, height: h)
            }
            .onEnded { value in
                guard slideshowVM == nil else { dragOffset = .zero; return }
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let h = value.translation.height
                let w = value.translation.width
                let verticalDominant = abs(h) > abs(w) * 1.2

                guard !isZoomed, verticalDominant else {
                    dragOffset = .zero
                    return
                }

                // Upward swipe (1x) → open the info sheet. The bottom chrome
                // (filmstrip / bottom bar) is excluded from the gesture.
                if h < 0, value.startLocation.y < maxSwipeUpStartY(screenHeight: screenHeight, safeAreaBottom: safeAreaBottom) {
                    if PhotoViewerSwipeDecision.shouldOpen(progress: h / 300, velocity: velocity) {
                        openInfo()
                    }
                    return
                }

                // Downward swipe (1x) → dismiss the viewer.
                if h > 0 {
                    if PhotoViewerSwipeDecision.shouldClose(progress: dismissProgress, velocity: velocity) {
                        dismissAction()
                    } else {
                        withAnimation(PVMotion.adaptive(PVMotion.snappy, reduceMotion: reduceMotion)) {
                            dragOffset = .zero
                        }
                    }
                    return
                }

                dragOffset = .zero
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
    @State private var saveVM: SaveToLibraryViewModel?
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
            let saver = SaveToLibraryViewModel(asset: asset, client: client, baseURL: baseURL, token: token)
            saveVM = saver
        }
        .sensoryFeedback(.success, trigger: vm?.lastCreatedAlbumId)
        .sensoryFeedback(.success, trigger: vm?.lastAddedAlbumId)
        .sensoryFeedback(.success, trigger: saveVM?.lastSavedIdentifier)
        .sensoryFeedback(.success, trigger: saveVM?.didPresentDownload)
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
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
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
            if let saveVM {
                SaveSection(saveVM: saveVM)
            }

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
        do {
            let (data, contentType) = try await AssetFileTransfer.fetchData(from: url, token: token, session: .shared)

            // The bytes actually being shared win for the extension (preview
            // accuracy); fall back to the original mime, then jpg.
            let ext = AssetFileTransfer.fileExtension(forMime: contentType ?? originalMime)
            let base = AssetFileTransfer.baseName(
                originalName: originalName,
                datePrefix: String(asset.fileCreatedAt.prefix(10))
            )
            let fileURL = try AssetFileTransfer.writeTempFile(data: data, name: "\(base).\(ext)")
            ActivityPresenter.present(items: [fileURL]) {
                // Remove the whole unique temp directory.
                try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            }
        } catch {}
    }
}

// MARK: - Save section

/// "Save to Photos" / "Download original" actions atop the share sheet.
private struct SaveSection: View {
    @Bindable var saveVM: SaveToLibraryViewModel

    var body: some View {
        Section {
            Button {
                Task { await saveVM.saveToPhotos() }
            } label: {
                HStack(spacing: PVSpacing.s12) {
                    Label("Save to Photos", systemImage: "photo.badge.plus")
                    Spacer()
                    saveIndicator(
                        isBusy: saveVM.isSaving,
                        done: saveVM.lastSavedIdentifier != nil
                    )
                }
            }
            .disabled(saveVM.isSaving)

            Button {
                Task { await saveVM.downloadOriginal() }
            } label: {
                HStack(spacing: PVSpacing.s12) {
                    Label("Download original", systemImage: "arrow.down.circle")
                    Spacer()
                    saveIndicator(
                        isBusy: saveVM.isDownloading,
                        done: saveVM.didPresentDownload
                    )
                }
            }
            .disabled(saveVM.isDownloading)

            if let message = saveVM.errorMessage {
                Text(message)
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichError)
            }
        } header: {
            Text("Save")
        }
    }

    @ViewBuilder
    private func saveIndicator(isBusy: Bool, done: Bool) -> some View {
        if isBusy {
            ProgressView()
        } else if done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.immichSuccess)
        }
    }
}

// MARK: - System share presenter

/// Presents `UIActivityViewController` from the top-most presented controller.
@MainActor
enum ActivityPresenter {
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
            AssetReactItem(id: "p1", ownerId: "o", ratio: 0.75, isFavorite: false, visibility: "timeline", isTrashed: false, isImage: true, thumbhash: nil, createdAt: "2024-07-29T10:00:00.000Z", fileCreatedAt: "2024-07-29T10:00:00.000Z", localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil, city: "Paris", country: "France", latitude: nil, longitude: nil, stack: []),
            AssetReactItem(id: "p2", ownerId: "o", ratio: 1.5, isFavorite: true, visibility: "timeline", isTrashed: false, isImage: true, thumbhash: nil, createdAt: "2024-07-30T10:00:00.000Z", fileCreatedAt: "2024-07-30T10:00:00.000Z", localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil, city: nil, country: "France", latitude: nil, longitude: nil, stack: [])
        ],
        index: 0,
        baseURL: URL(string: "https://example.com")!,
        token: nil
    )
}
#endif
