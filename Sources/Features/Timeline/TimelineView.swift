import SwiftUI

/// Main photo-grid timeline — Apple-Photos-grade premium experience.
///
/// Visual layers (AC-V01..V07):
/// - Large "Photos" title (collapsing); selection overrides to "X selected".
/// - SF Symbol toolbar (xmark cancel; selection-mode favorite/delete/add-to-album).
/// - Photos-style pinch-to-zoom grid (2-7 columns) via `TimelineGridZoom`.
/// - Skeleton shimmer grid for loading (4×3 initial, 1×3 load-more).
/// - `ContentUnavailableView` empty + error states.
/// - Human-relative date headers via `DateHeaderFormatter`.
/// - Spring-animated selection mode w/ pro cell treatment (scale, tint, symbol morph).
/// - Pull-to-refresh, scroll-to-top, pinned headers, sensoryFeedback.
struct TimelineView: View {
    @State private var vm: TimelineViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Grid zoom (Photos-style pinch): 2-7 columns, default 3. `gridScale`
    // persists the committed zoom between gestures; the live pinch multiplier
    // folds in during `MagnifyGesture.onChanged`.
    private let defaultColumnCount = 3
    private let minColumnCount = 2
    private let maxColumnCount = 7
    @State private var columnCount = 3
    @State private var gridScale: CGFloat = 1.0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: columnCount)
    }

    // UI-only haptic / scroll state (not VM concerns).
    // Pinned header shows the day group whose grid currently owns the top
    // edge; month-year derives from it (flips only on month change).
    @State private var pinnedDay: String?
    @State private var showScrollToTop = false
    @State private var lastFavoriteTick = 0
    @State private var lastDeleteTick = 0
    @State private var lastSelectionTick = 0
    @State private var pendingDeleteSelected = false
    @State private var pendingDeleteSingleID: String?
    @State private var presentAlbumPicker = false // AC-515 — Add to Album sheet
    @State private var viewerItem: PhotoViewerItem? // Full-screen photo viewer

    init(vm: TimelineViewModel) {
        _vm = State(initialValue: vm)
    }

    var body: some View {
        @Bindable var auth = auth
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // Top sentinel — when it scrolls off, show the ↑ button.
                    Color.clear
                        .frame(height: 1)
                        .id("top")
                        .onAppear { showScrollToTop = false }
                        .onDisappear { showScrollToTop = true }

                    content
                }
                .coordinateSpace(name: Self.scrollSpaceName)
                .onPreferenceChange(PinnedDayPreferenceKey.self) { frames in
                    pinnedDay = PinnedHeaderResolver.currentDay(from: frames)
                }
                // Photos-style pinned year + day (D8): floats over the grid,
                // top-left, no background — photos slide beneath. White text +
                // subtle shadow keeps it readable over any photo (Photos app
                // look). Year flips only at year boundaries; day per day.
                .overlay(alignment: .topLeading) {
                    if let day = pinnedDay, !vm.selectionMode {
                        VStack(alignment: .leading, spacing: PVSpacing.s2) {
                            Text(DateHeaderFormatter.yearString(for: day))
                                .font(.pvTitle)
                                .foregroundStyle(Color.white)
                            Text(DateHeaderFormatter.dayMonthString(for: day))
                                .font(.pvSubhead.weight(.bold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, PVSpacing.s16)
                        .padding(.trailing, PVSpacing.s4)
                        .padding(.top, PVSpacing.s8)
                        .padding(.bottom, PVSpacing.s4)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1) // DS-exempt: contrast over photos
                        .accessibilityAddTraits(.isHeader)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Explicit "Select" entry point (Photos-style): a liquid
                    // glass pill that rides alongside the pinned date header.
                    // Long-press entry still works; this makes selection
                    // discoverable for mass/bulk actions. Hidden once selection
                    // mode is active (toolbar takes over).
                    if pinnedDay != nil && !vm.selectionMode {
                        GlassEffectContainer {
                            Button {
                                vm.enterSelectionMode()
                            } label: {
                                Text("Select")
                                    .font(.pvHeadline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, PVSpacing.s16)
                                    .padding(.vertical, PVSpacing.s8)
                                    // Dark-tinted glass for legibility over
                                    // photos (shared-album badge recipe).
                                    .glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .accessibilityIdentifier("selectButton")
                        .padding(.trailing, PVSpacing.s16)
                        .padding(.top, PVSpacing.s8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .refreshable { await vm.refresh() }
                .scrollDismissesKeyboard(.immediately)
                // D7: Photos-style pinch-to-zoom grid. Simultaneous so it never
                // blocks tap/long-press/scroll. `gridScale` commits on end, so
                // the zoom level persists across gestures (Photos behavior).
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            columnCount = TimelineGridZoom.columns(
                                forEffectiveScale: TimelineGridZoom.effectiveScale(
                                    base: gridScale,
                                    magnification: value.magnification,
                                    defaultColumns: defaultColumnCount,
                                    minColumns: minColumnCount,
                                    maxColumns: maxColumnCount
                                ),
                                defaultColumns: defaultColumnCount,
                                minColumns: minColumnCount,
                                maxColumns: maxColumnCount
                            )
                        }
                        .onEnded { value in
                            gridScale = TimelineGridZoom.effectiveScale(
                                base: gridScale,
                                magnification: value.magnification,
                                defaultColumns: defaultColumnCount,
                                minColumns: minColumnCount,
                                maxColumns: maxColumnCount
                            )
                        }
                )
                // D6: tap on empty grid area exits selection mode. Cell taps
                // win via their own onTapGesture (hit-tested first).
                .onTapGesture {
                    if vm.selectionMode { vm.exitSelectionMode() }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showScrollToTop && !vm.selectionMode {
                        Button {
                            withAnimation(PVMotion.adaptive(PVMotion.gentle, reduceMotion: reduceMotion)) {
                                proxy.scrollTo("top", anchor: .top)
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.pvHeadline)
                                .foregroundStyle(Color.immichPrimary)
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .pvFloatingShadow()
                        }
                        .accessibilityLabel(String(localized: "Scroll to top"))
                        .padding(.trailing, PVSpacing.s16)
                        .padding(.bottom, PVSpacing.s24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .navigationTitle(vm.selectionMode ? "\(vm.selectedIds.count) selected" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                // Photos-style: no top bar normally (photos start right under
                // the island); the bar returns in selection mode for the
                // xmark + favorite/delete/add-to-album controls.
                .toolbar(vm.selectionMode ? .visible : .hidden, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .sensoryFeedback(.selection, trigger: vm.selectionMode)
            .sensoryFeedback(.selection, trigger: lastSelectionTick)
            .sensoryFeedback(.success, trigger: lastFavoriteTick)
            .sensoryFeedback(.warning, trigger: lastDeleteTick)
            // Spring on selection-mode transitions (AC-V04).
            .animation(PVMotion.standard, value: vm.selectionMode)
        }
        .task {
            if vm.items.isEmpty {
                await vm.load()
            }
        }
        .alert("Delete \(vm.selectedIds.count) asset(s)?", isPresented: $pendingDeleteSelected) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteSelected()
                    lastDeleteTick &+= 1
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from your library. Action cannot be undone.")
        }
        // D3: surface VM errors (favorite/delete/load failures) — never swallow silently.
        .alert("Something went wrong", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        // D5: single-asset context-menu delete confirmation.
        .alert("Delete this asset?", isPresented: Binding(
            get: { pendingDeleteSingleID != nil },
            set: { if !$0 { pendingDeleteSingleID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteSingleID {
                    Task {
                        await vm.delete(id: id)
                        lastDeleteTick &+= 1
                    }
                }
                pendingDeleteSingleID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSingleID = nil }
        } message: {
            Text("This removes it from your library. Action cannot be undone.")
        }
        // AC-515 — Add to Album picker (shares AlbumsViewModel via environment, FM-3).
        .sheet(isPresented: $presentAlbumPicker) {
            AddToAlbumPickerSheet(selectedAssetIds: vm.selectedIds) {
                vm.exitSelectionMode()
            }
        }
        // Full-screen photo viewer (tap any photo → Photos-style browse/zoom).
        .photoViewer(
            item: $viewerItem,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            onToggleFavorite: { asset in
                Task {
                    await vm.toggleFavorite(id: asset.id)
                    lastFavoriteTick &+= 1
                }
            },
            onDelete: { asset in
                Task { await vm.delete(id: asset.id) }
            }
        )
    }

    // MARK: - Content (skeleton / empty / grid)

    @ViewBuilder
    private var content: some View {
        if vm.items.isEmpty {
            if vm.isLoading {
                PVSkeletonGrid(rows: 4, columnCount: columnCount)
                    .padding(.horizontal, PVSpacing.s4)
                    .padding(.top, PVSpacing.s4)
            } else if vm.errorMessage != nil {
                ContentUnavailableView {
                    Label("Couldn't load photos", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(vm.errorMessage ?? "")
                } actions: {
                    Button("Try Again") { Task { await vm.refresh() } }
                        .buttonStyle(PVPrimaryButtonStyle())
                }
                .padding(.top, 80)
            } else {
                ContentUnavailableView {
                    Label("No Photos", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Photos you upload to Immich will appear here.")
                } actions: {
                    Button("Refresh") { Task { await vm.refresh() } }
                }
                .padding(.top, 80)
            }
        } else {
            // Continuous grid (Photos-style): ONE LazyVGrid across all day
            // groups so rows always fill completely — no empty trailing cells
            // from per-day grid restarts. No per-day labels: the floating
            // month/day header is driven by the first item cell of each day.
            LazyVStack(alignment: .leading, spacing: PVSpacing.s2) {
                LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                    ForEach(timelineSections) { section in
                        switch section {
                        case .monthHeader(_, _):
                            // Month banner retired — the sticky header carries it.
                            EmptyView()

                        case .dayGroup(let group):
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                cellView(for: item)
                                    .task {
                                        // Global last-item trigger — stays correct
                                        // under section restructure because the
                                        // id compared is the VM's flat last id.
                                        if item.id == vm.items.last?.id {
                                            await vm.loadMore()
                                        }
                                    }
                                    // First cell of each day reports the day's
                                    // start edge (its grid position) so the
                                    // floating header resolves the current day.
                                    .background {
                                        if index == 0 {
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: PinnedDayPreferenceKey.self,
                                                    value: [group.day: proxy.frame(in: .named(Self.scrollSpaceName)).minY]
                                                )
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, PVSpacing.s4)
                if vm.canLoadMore {
                    PVSkeletonGrid(rows: 1, columnCount: columnCount)
                        .padding(.horizontal, PVSpacing.s4)
                        .padding(.top, PVSpacing.s4)
                }
            }
        }
    }

    // MARK: - Timeline sections (month interleaving)

    /// Typealias so the View reads the builder's `Section` enum without
    /// re-declaring it (single source of truth in `TimelineSectionBuilder`).
    private typealias TimelineSection = TimelineSectionBuilder.Section

    /// Interleaves month-year banners between day groups when the month
    /// changes. Memoized on the VM (audit P1) so the section pipeline runs
    /// only when `items` changes, not on every body evaluation.
    private var timelineSections: [TimelineSection] {
        vm.timelineSections
    }

    // MARK: - Cell container — navigation vs selection-aware tap

    @ViewBuilder
    private func cellView(for item: AssetReactItem) -> some View {
        let cell = AssetThumbnailCell(
            asset: item,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            selectionMode: vm.selectionMode,
            isSelected: vm.selectedIds.contains(item.id),
            onTap: {
                if vm.selectionMode {
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                } else {
                    openViewer(for: item)
                }
            },
            onToggleFavorite: {
                Task {
                    await vm.toggleFavorite(id: item.id)
                    lastFavoriteTick &+= 1
                }
            },
            onDelete: {
                pendingDeleteSingleID = item.id
            }
        )
        .buttonStyle(.plain)

        if vm.selectionMode {
            cell
                .onLongPressGesture(minimumDuration: 0.4) {
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                }
        } else {
            cell
                .onLongPressGesture(minimumDuration: 0.4) {
                    vm.enterSelectionMode()
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                }
        }
    }

    // MARK: - Full-screen photo viewer

    /// Opens the Photos-style viewer at `item`, paging through the flat
    /// timeline order (matches grid visual order — `groupedByDay` preserves it).
    private func openViewer(for item: AssetReactItem) {
        guard let idx = vm.items.firstIndex(where: { $0.id == item.id }) else { return }
        viewerItem = PhotoViewerItem(assets: vm.items, index: idx)
    }

    // MARK: - Toolbar — swaps between normal + selection modes (SF Symbols, V03)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if vm.selectionMode {
                Button {
                    vm.exitSelectionMode()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if vm.selectionMode {
                Button {
                    Task {
                        let target = !vm.selectedIds.allSatisfy { id in
                            vm.items.first { $0.id == id }?.isFavorite ?? false
                        }
                        // Exit only on success so a failed batch keeps the
                        // selection intact for retry (audit fix — mirrors
                        // deleteSelected's try-then-mutate discipline).
                        if await vm.batchSetFavorite(vm.selectedIds, favorite: target) {
                            vm.exitSelectionMode()
                        }
                        lastFavoriteTick &+= 1
                    }
                } label: {
                    Label("Favorite", systemImage: "heart")
                        .labelStyle(.iconOnly)
                }
                .disabled(vm.selectedIds.isEmpty)

                Button(role: .destructive) {
                    pendingDeleteSelected = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(vm.selectedIds.isEmpty)

                // AC-515 — Add to Album. Opens picker sheet w/ selected assets.
                Button {
                    presentAlbumPicker = true
                } label: {
                    Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(vm.selectedIds.isEmpty)
                .accessibilityIdentifier("addToAlbumButton")
            }
        }
    }
}

// MARK: - Pinned header support

/// Coordinate space each day grid reports its top edge into.
private extension TimelineView {
    static let scrollSpaceName = "timeline"
}

/// Collects each visible day grid's top edge (`minY`) in the timeline's
/// coordinate space. LazyVStack instantiates only on-screen grids, so the
/// dictionary stays small; `PinnedHeaderResolver` turns it into a day.
private struct PinnedDayPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
