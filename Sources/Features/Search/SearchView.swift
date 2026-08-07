import SwiftUI

/// Search tab — Apple-Photos-like search with three modes (Results | Explore | Map).
///
/// - **Results**: native `.searchable` field with debounced live search.
///   LazyVGrid of `AssetThumbnailCell` (corner radius 0 — project convention).
///   Tap → `AssetDetailView` (NavigationLink pattern from TimelineView.swift:253).
///   Smart/Metadata mode toggle lives in a toolbar `Menu` (default Smart/CLIP).
/// - **Explore**: curated city/object suggestions via `GET /api/search/explore`.
///   Tap a card → `searchByCity(_:)` filters results by that city.
/// - **Map**: clustered MapKit view of all geolocated photos (AC-710).
///
/// People / faces deferred to a future iteration (cahier L136).
struct SearchView: View {
    @Bindable var vm: SearchViewModel
    @Bindable var mapVM: MapViewModel
    @Environment(AuthViewModel.self) private var auth

    @State private var viewerItem: PhotoViewerItem? // Full-screen photo viewer

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

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
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if vm.viewMode == .results {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            searchModeMenu
                        }
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.immichPrimary)
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: Circle())
        }
        .accessibilityLabel("Search mode: \(vm.searchMode == .smart ? "Smart" : "Metadata")")
    }

    @ViewBuilder
    private var searchSuggestions: some View {
        if vm.query.isEmpty {
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
            VStack(alignment: .leading, spacing: PVSpacing.s4) {
                Text("\(vm.results.count) photos")
                    .font(.pvSubhead)
                    .foregroundStyle(Color.textSecondaryPV)
                    .padding(.horizontal)
                    .padding(.top, PVSpacing.s8)

                LazyVGrid(columns: columns, spacing: 0) {
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
        if vm.exploreData.isEmpty {
            ContentUnavailableView(
                "No suggestions available",
                systemImage: "safari",
                description: Text("Explore requires photos with EXIF metadata or recognized places.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PVSpacing.s16) {
                    ForEach(Array(vm.exploreData.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: PVSpacing.s8) {
                            Text(Self.prettyFieldName(section.fieldName))
                                .font(.pvHeadline)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: PVSpacing.s8) {
                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        Button {
                                            Task { await vm.searchByCity(item.value) }
                                        } label: {
                                            exploreCard(value: item.value, item: item.data)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(vm.isLoading)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical, PVSpacing.s8)
            }
        }
    }

    @ViewBuilder
    private func exploreCard(value: String, item: AssetResponseDto) -> some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            let url = AssetReactItem(from: item).thumbnailURL(
                base: auth.baseURL ?? URL(string: "https://example.com")!
            )
            AuthenticatedAsyncImage(url: url, token: auth.accessToken)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.none, style: .continuous))
            Text(value)
                .font(.pvSubhead)
                .lineLimit(1)
        }
        .frame(width: 140)
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

    /// Translates Immich field names (e.g. "exifInfo.city") into human labels.
    private static func prettyFieldName(_ raw: String) -> String {
        switch raw {
        case "exifInfo.city": return "Places"
        case "exifInfo.country": return "Countries"
        case "exifInfo.make": return "Cameras"
        case "exifInfo.model": return "Models"
        default: return raw
        }
    }
}
