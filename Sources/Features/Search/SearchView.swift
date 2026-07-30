import SwiftUI

/// Search tab — Apple-Photos-like search with two modes (Results | Explore).
///
/// - **Results**: free-text search via `Picker` (Metadata | Smart). LazyVGrid
///   of `AssetThumbnailCell` (corner radius 0 — project convention). Tap →
///   `AssetDetailView` (NavigationLink pattern from TimelineView.swift:253).
/// - **Explore**: curated city/object suggestions via `GET /api/search/explore`.
///   Tap a card → `searchByCity(_:)` filters results by that city.
///
/// People / faces deferred to a future iteration (cahier L136).
struct SearchView: View {
    @Bindable var vm: SearchViewModel
    @Environment(AuthViewModel.self) private var auth

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                modePicker
                Divider()
                content
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Search bar + mode pickers

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search photos, places, and people", text: $vm.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { Task { await vm.search() } }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var modePicker: some View {
        VStack(spacing: 4) {
            Picker("View", selection: $vm.viewMode) {
                Text("Results").tag(SearchViewModel.ViewMode.results)
                Text("Explore").tag(SearchViewModel.ViewMode.explore)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            if vm.viewMode == .results {
                Picker("Search Mode", selection: $vm.searchMode) {
                    Text("Metadata").tag(SearchViewModel.SearchMode.metadata)
                    Text("Smart").tag(SearchViewModel.SearchMode.smart)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Content (results grid | explore cards | empty | loading | error)

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.results.isEmpty && vm.viewMode == .results {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.errorMessage {
            errorView(msg)
        } else if vm.viewMode == .results {
            resultsView
        } else {
            exploreView
                .task {
                    // AC-404a / AC-404c: load explore once per VM lifetime.
                    await vm.loadExplore()
                }
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if vm.results.isEmpty {
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
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(vm.results) { item in
                        NavigationLink {
                            AssetDetailView(asset: item)
                        } label: {
                            AssetThumbnailCell(
                                asset: item,
                                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                                token: auth.accessToken,
                                onTap: {
                                    Task { await vm.loadMore() }
                                }
                            )
                            .buttonStyle(.plain)
                        }
                        .task {
                            // AC-406: trigger next page when near the end.
                            if item.id == vm.results.last?.id {
                                await vm.loadMore()
                            }
                        }
                    }
                }
                if vm.isLoading {
                    ProgressView()
                        .padding(.vertical, 12)
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
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(vm.exploreData.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.prettyFieldName(section.fieldName))
                                .font(.headline)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
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
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func exploreCard(value: String, item: AssetResponseDto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let url = AssetReactItem(from: item).thumbnailURL(
                base: auth.baseURL ?? URL(string: "https://example.com")!
            )
            AuthenticatedAsyncImage(url: url, token: auth.accessToken)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
        }
        .frame(width: 140)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .foregroundStyle(.secondary)
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
