import SwiftUI

/// Albums tab (AC-514). A Photos-style grid of premium portrait album cards;
/// tapping a card zoom-morphs into `AlbumDetailView`. The `+` toolbar button
/// and the empty-state CTA present `CreateAlbumSheet`.
///
/// Navigation follows Apple HIG for a top-level content tab: a native large,
/// scroll-collapsing title (`.large`) — no custom brand wordmark in the toolbar.
///
/// `AlbumsViewModel` is injected via `@Environment` from RootView so the
/// Timeline "Add to Album" picker shares the same instance (FM-3 mitigation).
struct AlbumsView: View {
    @Bindable var vm: AlbumsViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentingCreate = false
    @State private var openTick = 0
    @Namespace private var albumNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s12), count: 2)

    var body: some View {
        NavigationStack {
            Group {
                if vm.albums.isEmpty && vm.errorMessage != nil && !vm.isLoading {
                    errorState
                } else if vm.isLoading && vm.albums.isEmpty {
                    ScrollView {
                        PVSkeletonGrid(rows: 4, columnCount: 2)
                            .padding(.horizontal, PVSpacing.s4)
                            .padding(.top, PVSpacing.s4)
                    }
                } else if vm.albums.isEmpty {
                    emptyState
                } else {
                    albumGrid
                }
            }
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $presentingCreate) {
                CreateAlbumSheet(vm: vm, preselectedAssetIds: nil)
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil && !vm.albums.isEmpty },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - States

    private var errorState: some View {
        ContentUnavailableView {
            Label("Couldn't load albums", systemImage: "wifi.exclamationmark")
        } description: {
            Text(vm.errorMessage ?? "")
        } actions: {
            Button("Try Again") { Task { await vm.refresh() } }
                .buttonStyle(PVPrimaryButtonStyle())
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 56)) // DS-exempt: hero illustration §8.6
                .foregroundStyle(Color.textTertiaryPV)
            Text("No albums yet")
                .font(.pvTitle)
        } description: {
            Text("Create an album to organize your photos.")
        } actions: {
            Button("Create Album") { presentingCreate = true }
                .buttonStyle(PVPrimaryButtonStyle())
                .padding(.horizontal, PVSpacing.s48)
        }
    }

    // MARK: - Grid

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: PVSpacing.s16) {
                ForEach(vm.albums, id: \.id) { album in
                    NavigationLink {
                        AlbumDetailView(
                            albumId: album.id,
                            albumName: album.albumName,
                            namespace: albumNamespace,
                            sourceID: album.id
                        )
                        .navigationTransition(.zoom(sourceID: album.id, in: albumNamespace))
                    } label: {
                        AlbumCard(
                            album: album,
                            baseURL: auth.baseURL ?? defaultBaseURL,
                            token: auth.accessToken,
                            showsShadow: colorScheme == .light
                        )
                    }
                    .buttonStyle(AlbumCardPressStyle(reduceMotion: reduceMotion))
                    .matchedTransitionSource(id: album.id, in: albumNamespace)
                    .simultaneousGesture(TapGesture().onEnded { openTick &+= 1 })
                }
            }
            .padding(.horizontal, PVSpacing.s4)
            .padding(.top, PVSpacing.s4)
        }
    }

    private var defaultBaseURL: URL { URL(string: "https://example.com")! }

    // MARK: - Card

    /// Premium portrait (3:4) album card. Opaque content surface (glass is for
    /// the control layer per WWDC25-219/356 — never the photo), 16pt continuous
    /// corners, a soft diffuse shadow in light mode, and title + count beneath.
    /// A glass "shared" badge floats on the cover when the album is collaborative.
    fileprivate struct AlbumCard: View {
        let album: AlbumResponseDto
        let baseURL: URL
        let token: String?
        let showsShadow: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: PVSpacing.s4) {
                cover
                VStack(alignment: .leading, spacing: PVSpacing.s2) {
                    Text(album.albumName)
                        .font(.pvHeadline)
                        .foregroundStyle(Color.textPrimaryPV)
                        .lineLimit(1)
                    Text("\(album.assetCount) Photos")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                .padding(.leading, PVSpacing.s4)
            }
            .shadow(color: .black.opacity(showsShadow ? 0.12 : 0), radius: showsShadow ? 8 : 0, x: 0, y: 4)
        }

        private var cover: some View {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if let thumbId = album.albumThumbnailAssetId {
                        AuthenticatedAsyncImage(
                            url: ImmichAssetURL.thumbnail(assetId: thumbId, thumbhash: "", baseURL: baseURL),
                            token: token
                        )
                    } else {
                        ZStack {
                            Color.bgTertiary
                            Image(systemName: "rectangle.stack")
                                .font(.pvTitleXL)
                                .foregroundStyle(Color.textSecondaryPV)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if album.shared {
                        GlassEffectContainer {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(PVSpacing.s4)
                                .glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
                                .padding(PVSpacing.s4)
                        }
                        .accessibilityLabel("Shared album")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
        }
    }
}

/// Press style for album cards: a subtle 0.97 scale-down spring on tap
/// (the premium, system-consistent touch feedback). Disabled under Reduce Motion.
struct AlbumCardPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : PVMotion.snappy, value: configuration.isPressed)
    }
}
