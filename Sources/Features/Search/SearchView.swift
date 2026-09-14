import SwiftUI

/// Search tab — Apple-Photos-like search with three modes (Results | Explore | Map).
///
/// - **Results**: native `.searchable` field with debounced live search.
///   LazyVGrid of `AssetThumbnailCell` (corner radius 0 — project convention).
///   Tap → `AssetDetailView` (NavigationLink pattern from TimelineView.swift:253).
///   Smart/Metadata mode toggle lives in a toolbar `Menu` (default Smart/CLIP).
/// - **Explore**: a vertical list of every place you've photographed, powered by
///   `GET /api/search/cities` (one representative asset per city) + per-place
///   counts from `POST /api/search/statistics`. Tap a card →
///   `searchByExplore(field: .city, value:)` filters results by that city.
/// - **Map**: clustered MapKit view of all geolocated photos (AC-710).
///
/// People / faces deferred to a future iteration (cahier L136).
struct SearchView: View {
    @Bindable var vm: SearchViewModel
    @Bindable var mapVM: MapViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.openProfile) private var openProfile

    @State private var viewerItem: PhotoViewerItem? // Full-screen photo viewer
    @State private var showSaveSearch = false
    @State private var saveSearchName = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        NavigationStack {
            modeContent
                .onChange(of: vm.viewMode) { _, newMode in
                    // Leaving the map segment takes the map photo sheet down
                    // (and clears any marker filter) — the sheet is owned by
                    // RootView and would otherwise stay open over the other
                    // segments.
                    if newMode != .map {
                        mapVM.isPhotoSheetPresented = false
                        mapVM.deselectMarker()
                    }
                }
                // Floating Liquid-Glass segmented control over all three modes.
                // The map ignores the safe area and extends *under* this pill
                // (Apple Maps-style); Résultats/Explorer content sits below it.
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Compact pill centered with guaranteed side margins (never
                    // kisses the screen edges).
                    HStack {
                        Spacer(minLength: PVSpacing.s16)
                        SearchModeGlassBar(mode: $vm.viewMode)
                        Spacer(minLength: PVSpacing.s16)
                    }
                    .padding(.top, PVSpacing.s8)
                    .padding(.bottom, PVSpacing.s4)
                }
                // `verbatim`: the bar intentionally carries no title, and an
                // empty `LocalizedStringKey` would be extracted as a `""` key.
                .navigationTitle(Text(verbatim: ""))
                .navigationBarTitleDisplayMode(.inline)
                // Search-mode menu + avatar as a nav-bar row (topBarTrailing):
                // iOS 26 renders its own Liquid-Glass chrome, so no manual
                // glassEffect — a manual circle on the label would double-glass
                // and clip. Menu only in results mode; avatar always visible.
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if vm.viewMode == .results {
                            searchModeMenu
                            Button {
                                saveSearchName = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                showSaveSearch = true
                            } label: {
                                Image(systemName: "bookmark")
                            }
                            .disabled(vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Save search")
                        }
                        ProfileAvatarButton { openProfile() }
                    }
                }
                // Full-screen photo viewer (tap any result photo → browse/zoom).
                // Favorite/delete run self-sufficient; re-run the search so the
                // results grid reflects mutations after the viewer closes.
                .photoViewer(
                    item: $viewerItem,
                    baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                    token: auth.accessToken,
                    onDataChanged: {
                        Task { await vm.search() }
                    }
                )
                .alert("Save Search", isPresented: $showSaveSearch) {
                    TextField("Name", text: $saveSearchName)
                        .textInputAutocapitalization(.words)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {
                        vm.saveCurrentSearch(name: saveSearchName)
                    }
                } message: {
                    Text("Save the current search for quick access.")
                }
        }
    }

    /// The active mode's content. Results keeps the native `.searchable` field;
    /// Explore loads its curated suggestions once; Map is full-screen.
    @ViewBuilder
    private var modeContent: some View {
        switch vm.viewMode {
        case .results:
            resultsContent
                .searchable(
                    text: $vm.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search photos and places"
                )
                .onChange(of: vm.query) { _, _ in vm.queryDidChange() }
                .searchSuggestions { searchSuggestions }
        case .explore:
            exploreView
                .task {
                    // AC-404a / AC-404c: load explore once per VM lifetime.
                    await vm.loadExplore()
                }
        case .map:
            MapSegmentView(vm: mapVM)
        }
    }

    /// Opens the Photos-style viewer at `item`, paging through search results.
    private func openViewer(for item: AssetReactItem) {
        guard let idx = vm.results.firstIndex(where: { $0.id == item.id }) else { return }
        viewerItem = PhotoViewerItem(assets: vm.results, index: idx)
    }

    // MARK: - Shared chrome

    /// Smart (CLIP semantic) vs Metadata (EXIF fields) search — folded into a
    /// compact menu so the Results area stays uncluttered.
    private var searchModeMenu: some View {
        Menu {
            Picker("Search Mode", selection: $vm.searchMode) {
                Label("Smart", systemImage: "sparkles").tag(SearchViewModel.SearchMode.smart)
                Label("Metadata", systemImage: "character.magnify").tag(SearchViewModel.SearchMode.metadata)
            }
        } label: {
            Image(systemName: vm.searchMode == .smart ? "sparkles" : "character.magnify")
                .font(.pvBody.weight(.semibold))
                .foregroundStyle(Color.immichPrimary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Search mode: \(vm.searchMode == .smart ? "Smart" : "Metadata")")
    }

    @ViewBuilder
    private var searchSuggestions: some View {
        if vm.query.isEmpty {
            if !vm.savedSearches.isEmpty {
                Section("Saved") {
                    ForEach(vm.savedSearches) { saved in
                        Button {
                            Task { await vm.searchSaved(saved) }
                        } label: {
                            Label(saved.name, systemImage: "bookmark")
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.deleteSavedSearch(id: saved.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if !vm.recentSearches.isEmpty {
                Section("Recent") {
                    ForEach(vm.recentSearches, id: \.self) { term in
                        Button {
                            Task { await vm.searchRecent(term) }
                        } label: {
                            Label(term, systemImage: "clock")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Content (results grid | explore cards | map | loading | error)

    @ViewBuilder
    private var resultsContent: some View {
        if vm.isLoading && vm.results.isEmpty && vm.hasSearched {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.errorMessage {
            errorView(msg)
        } else if vm.results.isEmpty {
            if vm.hasSearched {
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Search your library",
                    systemImage: "magnifyingglass",
                    description: Text("Find photos by place, object, camera, or natural language.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            resultsGrid
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            // Mirrors the Photos timeline grid: LazyVStack + LazyVGrid with 2pt
            // seams and a 4pt horizontal inset — no count header above the grid.
            LazyVStack(alignment: .leading, spacing: PVSpacing.s2) {
                LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                    ForEach(vm.results) { item in
                        AssetThumbnailCell(
                            asset: item,
                            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                            token: auth.accessToken,
                            onTap: { openViewer(for: item) }
                        )
                        .buttonStyle(.plain)
                        .onAppear {
                            // AC-406: trigger next page when the last cell appears.
                            if item.id == vm.results.last?.id {
                                Task { await vm.loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, PVSpacing.s4)
                if vm.isLoading {
                    ProgressView()
                        .padding(.vertical, PVSpacing.s12)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var exploreView: some View {
        // Distinguish "loading first page" from "genuinely empty" so the user
        // sees a spinner on first open instead of the empty-state.
        if vm.explorePlaces.isEmpty && !vm.isLoading {
            ContentUnavailableView(
                "No places yet",
                systemImage: "mappin.and.ellipse",
                description: Text("Photos with a recognized location will appear here as places you can explore.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.explorePlaces.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: PVSpacing.s12) {
                    ForEach(vm.explorePlaces) { place in
                        Button {
                            Task { await vm.searchByExplore(field: .city, value: place.city) }
                        } label: {
                            ExplorePlaceCard(
                                place: place,
                                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                                token: auth.accessToken
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isLoading)
                    }
                }
                .padding(.horizontal, PVSpacing.s12)
                .padding(.vertical, PVSpacing.s8)
            }
            .refreshable { await vm.refreshExplore() }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: PVSpacing.s12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.pvTitle)
                .foregroundStyle(Color.immichWarning)
            Text(msg)
                .font(.pvBody)
                .foregroundStyle(Color.textSecondaryPV)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-width hero card for one place: a 3:2 representative photo with a
/// darkened bottom gradient and overlaid flag + city + state/country + photo
/// count + most-recent date. The thumbnail URL is precomputed once (preview
/// size for sharper hero imagery than the grid thumbnail).
private struct ExplorePlaceCard: View {
    let place: ExplorePlace
    let baseURL: URL
    let token: String?

    private let url: URL

    init(place: ExplorePlace, baseURL: URL, token: String?) {
        self.place = place
        self.baseURL = baseURL
        self.token = token
        self.url = ImmichAssetURL.thumbnail(
            assetId: place.assetId, thumbhash: place.thumbhash ?? "", baseURL: baseURL, size: .preview
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AuthenticatedAsyncImage(url: url, token: token)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

            // Legibility gradient under the text.
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 140)
            .allowsHitTesting(false)

            // Overlaid metadata.
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(headline)
                    .font(.pvH4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(radius: 4)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.pvSubhead)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(footer)
                    .font(.pvCaption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(PVSpacing.s12)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
        .pvFloatingShadow()
        .contentShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
    }

    /// "🇫🇷 Paris" or just "Paris" when no flag resolved.
    private var headline: String {
        if let flag = place.flag { return "\(flag) \(place.city)" }
        return place.city
    }

    /// "247 photos  ·  Jul 2024" — count shows a placeholder dash while loading.
    private var footer: String {
        var parts: [String] = []
        if let count = place.photoCount {
            parts.append("\(count) photos")
        } else {
            parts.append("·") // count still loading
        }
        if let date = place.date {
            parts.append(date.formatted(.dateTime.month(.abbreviated).year()))
        }
        return parts.joined(separator: "  ·  ")
    }
}
