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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if vm.viewMode == .results {
                    resultsStack
                        .searchable(
                            text: $vm.query,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search photos and places"
                        )
                        .onChange(of: vm.query) { _, _ in vm.queryDidChange() }
                        .searchSuggestions { searchSuggestions }
                } else {
                    VStack(spacing: 0) {
                        modePicker
                        Divider()
                        content
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ImmichAppBar()
                }
                if vm.viewMode == .results {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        searchModeMenu
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private var resultsStack: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            content
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $vm.viewMode) {
            Text("Results").tag(SearchViewModel.ViewMode.results)
            Text("Explore").tag(SearchViewModel.ViewMode.explore)
            Text("Map").tag(SearchViewModel.ViewMode.map)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, PVSpacing.s8)
        .padding(.bottom, PVSpacing.s4)
    }

    /// Smart (CLIP semantic) vs Metadata (EXIF fields) search — folded into a
    /// compact menu so the Results area stays uncluttered.
    private var searchModeMenu: some View {
        Menu {
            Picker("Search Mode", selection: $vm.searchMode) {
                Label("Smart", systemImage: "sparkles").tag(SearchViewModel.SearchMode.smart)
                Label("Metadata", systemImage: "character.magnify").tag(SearchViewModel.SearchMode.metadata)
            }
        } label: {
            Label(
                vm.searchMode == .smart ? "Smart" : "Metadata",
                systemImage: vm.searchMode == .smart ? "sparkles" : "character.magnify"
            )
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
    private var content: some View {
        switch vm.viewMode {
        case .results:
            resultsContent
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
                        NavigationLink {
                            AssetDetailView(asset: item)
                        } label: {
                            AssetThumbnailCell(
                                asset: item,
                                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                                token: auth.accessToken
                            )
                            .buttonStyle(.plain)
                        }
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
                .foregroundStyle(Color.statusPending)
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
