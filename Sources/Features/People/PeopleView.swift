import SwiftUI

/// People & faces (P3 people-faces): person list with face thumbnails and
/// asset counts, Featured section (favorites first), hidden-count footer row,
/// then a per-person drill-down: faces grid + rename / favorite / hide / merge.
/// Pushed from the Me tab (ProfileView) — no own NavigationStack (TrashView pattern).
struct PeopleView: View {
    @Bindable var vm: PeopleViewModel
    @Environment(AuthViewModel.self) private var auth

    @State private var viewerItem: PhotoViewerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        Group {
            if vm.isLoading && vm.people.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.people.isEmpty {
                ContentUnavailableView(
                    "No people yet",
                    systemImage: "person.2",
                    description: Text("Faces detected on your photos will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                personList
            }
        }
        .navigationTitle("People")
        .navigationDestination(for: PersonResponseDto.self) { person in
            PersonDetailView(vm: vm, person: person, columns: columns, viewerItem: $viewerItem)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.load(force: true); await vm.loadStatistics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh people")
            }
        }
        .task {
            await vm.load()
            await vm.loadStatistics()
        }
        .refreshable {
            await vm.load(force: true)
            await vm.loadStatistics()
        }
        .photoViewer(
            item: $viewerItem,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            onDataChanged: { Task { await vm.refreshAssets() } }
        )
    }

    // MARK: - List

    private var personList: some View {
        List {
            let featured = vm.people.filter { $0.isFavorite == true }
                .sorted { vm.assetCount(for: $0.id) > vm.assetCount(for: $1.id) }
            let rest = vm.people.filter { $0.isFavorite != true }
                .sorted { vm.assetCount(for: $0.id) > vm.assetCount(for: $1.id) }

            if !featured.isEmpty {
                Section("Featured") {
                    ForEach(featured) { person in
                        personRow(person)
                    }
                }
            }
            Section("People") {
                ForEach(rest) { person in
                    personRow(person)
                }
            }
            if vm.hiddenCount > 0 {
                Section {
                    Button {
                        Task { await vm.toggleShowHidden() }
                    } label: {
                        Label(
                            vm.showingHidden ? "Hide hidden people" : "Show \(vm.hiddenCount) hidden people",
                            systemImage: "eye.slash"
                        )
                        .font(.pvBody)
                        .foregroundStyle(Color.textSecondaryPV)
                    }
                }
            }
            if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.pvCaption)
                        .foregroundStyle(Color.immichError)
                }
            }
        }
    }

    private func personRow(_ person: PersonResponseDto) -> some View {
        NavigationLink(value: person) {
            HStack(spacing: PVSpacing.s12) {
                AuthenticatedAsyncImage(
                    url: ImmichAssetURL.personThumbnail(personId: person.id, baseURL: auth.baseURL ?? URL(string: "https://example.com")!),
                    token: auth.accessToken
                )
                .clipShape(Circle())
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(Color.separatorPV, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.pvBody)
                        .foregroundStyle(Color.textPrimaryPV)
                    Text("\(vm.assetCount(for: person.id)) photos")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                Spacer()
                if person.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.pvBody)
                        .foregroundStyle(Color.immichPrimary)
                }
            }
            .padding(.vertical, PVSpacing.s4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Faces drill-down: person header (avatar, name, count) + action toolbar
/// (favorite / rename / hide / merge) + 3-column faces grid with full viewer.
private struct PersonDetailView: View {
    @Bindable var vm: PeopleViewModel
    let person: PersonResponseDto
    let columns: [GridItem]
    @Binding var viewerItem: PhotoViewerItem?

    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        ScrollView {
            VStack(spacing: PVSpacing.s16) {
                AuthenticatedAsyncImage(
                    url: ImmichAssetURL.personThumbnail(
                        personId: person.id,
                        baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                        size: .preview
                    ),
                    token: auth.accessToken
                )
                .clipShape(Circle())
                .frame(width: 96, height: 96)
                .overlay(Circle().strokeBorder(Color.separatorPV, lineWidth: 1))

                VStack(spacing: 2) {
                    Text(person.name)
                        .font(.pvTitle)
                        .foregroundStyle(Color.textPrimaryPV)
                    Text("\(vm.assetCount(for: person.id)) photos")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }

                HStack(spacing: PVSpacing.s8) {
                    actionButton("star.fill", person.isFavorite == true ? Color.immichPrimary : Color.textSecondaryPV, "Favorite") {
                        Task { await vm.toggleFavorite(person) }
                    }
                    actionButton("pencil", .textSecondaryPV, "Rename") {
                        renameText = person.name
                        renamePerson = person
                    }
                    actionButton("eye.slash", .textSecondaryPV, person.isHidden ? "Unhide" : "Hide") {
                        Task { await vm.toggleHidden(person) }
                    }
                    mergeMenu
                }
            }
            .padding(.top, PVSpacing.s16)
            .padding(.horizontal, PVSpacing.s16)

            if vm.assetsLoading && vm.personAssets.isEmpty {
                ProgressView()
                    .padding(.vertical, PVSpacing.s32)
            } else if vm.personAssets.isEmpty {
                ContentUnavailableView(
                    "No photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("No assets tagged with this person yet.")
                )
                .padding(.vertical, PVSpacing.s24)
            } else {
                LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                    ForEach(Array(vm.personAssets.enumerated()), id: \.element.id) { i, item in
                        AssetThumbnailCell(
                            asset: item,
                            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                            token: auth.accessToken,
                            onTap: { viewerItem = PhotoViewerItem(assets: vm.personAssets, index: i) }
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, PVSpacing.s4)
            }

            if let error = vm.assetsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichError)
                    .padding(.vertical, PVSpacing.s8)
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.select(person) }
        .alert(
            "Rename Person",
            isPresented: Binding(
                get: { renamePerson != nil },
                set: { if !$0 { renamePerson = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let person = renamePerson {
                    Task { await vm.rename(person, to: renameText) }
                }
            }
        } message: {
            Text(person.name)
        }
    }

    @State private var renamePerson: PersonResponseDto?
    @State private var renameText = ""

    private func actionButton(_ systemName: String, _ color: Color, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.pvHeadline)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Color.gray.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var mergeMenu: some View {
        Menu {
            ForEach(vm.people.filter { $0.id != person.id }) { other in
                Button {
                    Task {
                        await vm.merge([other.id], into: person)
                    }
                } label: {
                    Label("Merge \(other.name)", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.merge")
                .font(.pvHeadline)
                .foregroundStyle(Color.textSecondaryPV)
                .frame(width: 40, height: 40)
                .background(Color.gray.opacity(0.12))
                .clipShape(Circle())
        }
        .disabled(vm.people.filter { $0.id != person.id }.isEmpty)
        .accessibilityLabel("Merge person")
    }
}