import SwiftUI

/// Main photo-grid timeline — Apple-Photos-grade premium experience.
///
/// Visual layers (AC-V01..V07):
/// - Large "Photos" title (collapsing); selection overrides to "X selected".
/// - SF Symbol toolbar (xmark cancel, portrait-arrow logout).
/// - Skeleton shimmer grid for loading (4×3 initial, 1×3 load-more).
/// - `ContentUnavailableView` empty + error states.
/// - Human-relative date headers via `DateHeaderFormatter`.
/// - Spring-animated selection mode w/ pro cell treatment (scale, tint, symbol morph).
/// - Pull-to-refresh, scroll-to-top, pinned headers, sensoryFeedback.
struct TimelineView: View {
    @State private var vm: TimelineViewModel
    @Environment(AuthViewModel.self) private var auth

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    // UI-only haptic / scroll state (not VM concerns).
    @State private var showScrollToTop = false
    @State private var lastFavoriteTick = 0
    @State private var lastDeleteTick = 0
    @State private var lastSelectionTick = 0
    @State private var pendingDeleteSelected = false
    @State private var pendingDeleteSingleID: String?
    @State private var presentAlbumPicker = false // AC-515 — Add to Album sheet

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
                .refreshable { await vm.refresh() }
                .scrollDismissesKeyboard(.immediately)
                // D6: tap on empty grid area exits selection mode. Cell taps
                // win via their own onTapGesture (hit-tested first).
                .onTapGesture {
                    if vm.selectionMode { vm.exitSelectionMode() }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showScrollToTop && !vm.selectionMode {
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo("top", anchor: .top)
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        }
                        .accessibilityLabel(String(localized: "Scroll to top"))
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .navigationTitle(vm.selectionMode ? "\(vm.selectedIds.count) selected" : "Photos")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .sensoryFeedback(.selection, trigger: vm.selectionMode)
            .sensoryFeedback(.selection, trigger: lastSelectionTick)
            .sensoryFeedback(.success, trigger: lastFavoriteTick)
            .sensoryFeedback(.warning, trigger: lastDeleteTick)
            // Spring on selection-mode transitions (AC-V04).
            .animation(.spring(duration: 0.35, bounce: 0.18), value: vm.selectionMode)
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
    }

    // MARK: - Content (skeleton / empty / grid)

    @ViewBuilder
    private var content: some View {
        if vm.items.isEmpty {
            if vm.isLoading {
                SkeletonShimmerGrid(rows: 4)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            } else if vm.errorMessage != nil {
                ContentUnavailableView {
                    Label("Couldn't load photos", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(vm.errorMessage ?? "")
                } actions: {
                    Button("Try Again") { Task { await vm.refresh() } }
                        .buttonStyle(.borderedProminent)
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
            // spacing: 0 — month banners carry vertical breathing room via
            // their own top padding (32pt). Pinned section headers sit flush.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(timelineSections) { section in
                    switch section {
                    case .monthHeader(_, let display):
                        MonthYearBanner(display: display)
                            .id(section.id)

                    case .dayGroup(let group):
                        Section {
                            LazyVGrid(columns: columns, spacing: 0) {
                                ForEach(group.items) { item in
                                    cellView(for: item)
                                        .task {
                                            // Global last-item trigger — stays correct
                                            // under section restructure because the
                                            // id compared is the VM's flat last id.
                                            if item.id == vm.items.last?.id {
                                                await vm.loadMore()
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 4)
                        } header: {
                            TimelineSectionHeader(
                                label: DateHeaderFormatter.displayString(for: group.day)
                            )
                        }
                        .id(section.id)
                    }
                }
                if vm.canLoadMore {
                    SkeletonShimmerGrid(rows: 1)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Timeline sections (month interleaving)

    /// Typealias so the View reads the builder's `Section` enum without
    /// re-declaring it (single source of truth in `TimelineSectionBuilder`).
    private typealias TimelineSection = TimelineSectionBuilder.Section

    /// Interleaves month-year banners between day groups when the month
    /// changes. Computed on every render — cheap (linear scan).
    private var timelineSections: [TimelineSection] {
        TimelineSectionBuilder.build(from: vm.groupedByDay)
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
                }
            },
            onToggleFavorite: {
                Task {
                    await vm.toggleFavorite(id: item.id)
                    lastFavoriteTick &+= 1
                }
            },
            onDelete: {
                if vm.selectionMode {
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                } else {
                    pendingDeleteSingleID = item.id
                }
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
            NavigationLink {
                AssetDetailView(asset: item)
            } label: {
                cell
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    vm.enterSelectionMode()
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                }
            )
        }
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
                        await vm.batchSetFavorite(vm.selectedIds, favorite: target)
                        lastFavoriteTick &+= 1
                        vm.exitSelectionMode()
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
            } else {
                // Premium account-style menu: tap the avatar opens a destructive
                // "Log Out" action. One extra tap isolates logout from fat-finger
                // taps (safer than a bare button in the corner).
                Menu {
                    Button(role: .destructive) {
                        Task { await auth.logout() }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
                .accessibilityLabel(String(localized: "Account"))
            }
        }
    }
}

// MARK: - Section header (refined typographic hierarchy)

private struct TimelineSectionHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.headline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Skeleton shimmer grid (V7)

/// Animated skeleton placeholder grid — N rows × 3 cols of square rounded
/// rectangles w/ a horizontal gradient sweep (clear → white → clear) over
/// `systemGray5`. NOT a spinner.
private struct SkeletonShimmerGrid: View {
    let rows: Int
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<(rows * 3), id: \.self) { _ in
                SkeletonCell()
            }
        }
    }
}

private struct SkeletonCell: View {
    @State private var phase: CGFloat = -1.2

    var body: some View {
        RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(Color(.systemGray5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // Narrow highlight band (~20% of width) for a crisp sweep
                // rather than a whole-cell brighten/dim (D4).
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.4),
                        .init(color: Color.white.opacity(0.4), location: 0.5),
                        .init(color: .clear, location: 0.6),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 240)
                .mask(RoundedRectangle(cornerRadius: 0, style: .continuous))
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
