import SwiftUI

/// "Shared" tab root (PRD §4). Lists ALL of the user's shared links (album and
/// individual), with copy-URL + revoke, pull-to-refresh, and a `+` to create a
/// new album-typed shared link. Backed by `SharedLinksViewModel`.
struct SharedLinksView: View {
    @State var vm: SharedLinksViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(AlbumsViewModel.self) private var albumsVM
    @Environment(\.openProfile) private var openProfile
    @State private var presentingCreate = false
    @State private var pendingRevokeId: String?
    @State private var showRevokeConfirm = false
    @State private var editLinkItem: EditLinkItem?

    init(vm: SharedLinksViewModel) {
        _vm = State(initialValue: vm)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.sharedLinks.isEmpty && vm.errorMessage != nil && !vm.isLoading {
                    ContentUnavailableView {
                        Label("Couldn't load shared links", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(vm.errorMessage ?? "")
                    } actions: {
                        Button("Try Again") { Task { await vm.refresh() } }
                            .buttonStyle(PVPrimaryButtonStyle())
                    }
                } else if vm.isLoading && vm.sharedLinks.isEmpty {
                    ProgressView()
                } else if vm.sharedLinks.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "link")
                            .font(.system(size: 56)) // DS-exempt: hero illustration §8.6
                            .foregroundStyle(Color.textTertiaryPV)
                        Text("No shared links")
                            .font(.pvTitle)
                    } description: {
                        Text("Links you create to share albums will appear here.")
                    } actions: {
                        Button("Create Link") { presentingCreate = true }
                            .buttonStyle(PVPrimaryButtonStyle())
                            .padding(.horizontal, PVSpacing.s48)
                    }
                } else {
                    linkList
                }
            }
            .navigationTitle("Shared")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton { openProfile() }
                }
            }
            .task {
                await vm.load()
                await albumsVM.load() // ensure album list is ready for the create picker
            }
            .refreshable {
                await vm.refresh()
            }
            .sheet(isPresented: $presentingCreate) {
                CreateSharedLinkSheet(vm: vm, baseURL: auth.baseURL ?? URL(string: "https://example.com")!)
            }
            .sheet(item: $editLinkItem) { item in
                EditSharedLinkSheet(link: item.link) { dto in
                    await vm.updateLink(id: item.link.id, dto: dto)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Revoke this shared link?", isPresented: $showRevokeConfirm) {
                Button("Revoke", role: .destructive) {
                    if let id = pendingRevokeId {
                        Task {
                            await vm.revoke(id: id)
                            // On success the row is gone from the data (it was
                            // already off-screen). On failure it slides back in.
                            withAnimation(PVMotion.snappy) {
                                pendingRevokeId = nil
                                showRevokeConfirm = false
                            }
                        }
                    } else {
                        withAnimation(PVMotion.snappy) {
                            showRevokeConfirm = false
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    withAnimation(PVMotion.snappy) {
                        pendingRevokeId = nil
                        showRevokeConfirm = false
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil && !vm.sharedLinks.isEmpty },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - List

    private var linkList: some View {
        let baseURL = auth.baseURL ?? URL(string: "https://example.com")!
        return List {
            ForEach(vm.sharedLinks, id: \.id) { link in
                SharedLinkRow(
                    link: link,
                    baseURL: baseURL,
                    isPendingRevoke: pendingRevokeId == link.id,
                    onRevoke: { pendingRevokeId = link.id }
                )
                .contextMenu {
                    Button {
                        editLinkItem = EditLinkItem(link: link)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingRevokeId = link.id
                        showRevokeConfirm = true
                    } label: {
                        Label("Revoke", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Revoke", systemImage: "trash", role: .destructive) {
                        withAnimation(PVMotion.snappy) {
                            pendingRevokeId = link.id
                        }
                        // Present the confirmation after the row has finished
                        // sliding out, so the popup never has to snap the row
                        // back from an open swipe state.
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard pendingRevokeId == link.id else { return }
                            showRevokeConfirm = true
                        }
                    }
                }
                .tint(.red)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// Identifiable wrapper for the edit sheet — `SharedLinkResponseDto` is not
/// `Identifiable`, and `.sheet(item:)` requires one. Shared by both edit
/// surfaces (Shared tab + album sheet).
struct EditLinkItem: Identifiable {
    let id = UUID()
    let link: SharedLinkResponseDto
}

// MARK: - Row

/// Card-style shared-link row. Swipe-to-revoke uses native List
/// `.swipeActions` (trailing destructive), wired to the same
/// confirmation-dialog flow as the card's `onRevoke` callback.
///
/// The card is never removed from the list while the confirmation is pending:
/// it slides out to the left (as if finishing the swipe) and slides back in
/// from the left on cancel, driven by a plain `offset` transform — the only
/// row animation that works reliably inside this List. With Reduce Motion
/// enabled the slide is replaced by an opacity crossfade.
struct SharedLinkRow: View {
    let link: SharedLinkResponseDto
    let baseURL: URL
    let isPendingRevoke: Bool
    let onRevoke: () -> Void
    var cardBackground: Color = Color.bgSecondary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var offsetX: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var rowHeight: CGFloat = 84

    private var url: String {
        baseURL.appendingPathComponent("/share/\(link.key)").absoluteString
    }

    private var title: String {
        if let album = link.album {
            if let desc = link.description, !desc.isEmpty {
                return "\(album.albumName) • \(desc)"
            }
            return album.albumName
        }
        if let desc = link.description, !desc.isEmpty { return desc }
        if !link.assets.isEmpty { return "\(link.assets.count) photo\(link.assets.count == 1 ? "" : "s")" }
        return "Untitled link"
    }

    var body: some View {
        cardContent
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { rowWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in
                            rowWidth = newWidth
                        }
                }
            }
            .offset(x: offsetX)
            .opacity(isPendingRevoke && reduceMotion ? 0 : 1)
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
            .allowsHitTesting(!isPendingRevoke)
            .onChange(of: isPendingRevoke) { _, isPending in
                withAnimation(PVMotion.snappy) {
                    if isPending {
                        // Slide the card out and collapse its cell so the list
                        // closes up behind it — no gap while the confirmation
                        // popup is up.
                        offsetX = -rowWidth
                        rowHeight = 0
                    } else {
                        // Reopen the cell and slide the card back in from the
                        // left.
                        offsetX = 0
                        rowHeight = 84
                    }
                }
            }
            .accessibilityAction(named: Text("Revoke")) { onRevoke() }
            // Row chrome: transparent background, no separator, and — while a
            // revoke is pending — zero insets + no minimum height so the cell
            // fully collapses (no residual gap during the confirmation popup).
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: isPendingRevoke ? 0 : PVSpacing.s4,
                leading: PVSpacing.s16,
                bottom: isPendingRevoke ? 0 : PVSpacing.s4,
                trailing: PVSpacing.s16
            ))
            .environment(\.defaultMinListRowHeight, isPendingRevoke ? 0 : 44)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            HStack(spacing: PVSpacing.s8) {
                // Type icon: album vs individual assets.
                Image(systemName: link.type == .album ? "rectangle.stack" : "photo")
                    .font(.pvBody)
                    .foregroundStyle(Color.textSecondaryPV)
                if link.password != nil {
                    Image(systemName: "lock.fill")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                Text(title)
                    .font(.pvSubhead)
                    .lineLimit(1)
                Spacer()
            }
            HStack {
                Text(url)
                    .font(.pvCaption).monospacedDigit()
                    .foregroundStyle(Color.textSecondaryPV)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = url
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(Color.immichPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PVSpacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
    }
}

// MARK: - Create sheet

/// Creates a new album-typed shared link. Picks an album from the user's list,
/// optional description + password. Reuses `SharedLinksViewModel.createAlbumLink`.
struct CreateSharedLinkSheet: View {
    @Bindable var vm: SharedLinksViewModel
    let baseURL: URL
    @Environment(AlbumsViewModel.self) private var albumsVM
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlbumId: String?
    @State private var description = ""
    @State private var usePassword = false
    @State private var password = ""
    @State private var createTick = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    if albumsVM.albums.isEmpty {
                        Text("You have no albums yet.")
                            .foregroundStyle(Color.textSecondaryPV)
                    } else {
                        Picker("Album", selection: $selectedAlbumId) {
                            ForEach(albumsVM.albums, id: \.id) { album in
                                Text(album.albumName).tag(Optional(album.id))
                            }
                        }
                    }
                }
                Section("Options") {
                    TextField("Description (optional)", text: $description)
                    Toggle("Password protect", isOn: $usePassword)
                    if usePassword {
                        SecureField("Password", text: $password)
                    }
                }
            }
            .navigationTitle("New Shared Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let albumId = selectedAlbumId else { return }
                        Task {
                            let ok = await vm.createAlbumLink(
                                albumId: albumId,
                                description: description.isEmpty ? nil : description,
                                password: usePassword ? password : nil
                            )
                            if ok {
                                createTick &+= 1
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedAlbumId == nil)
                }
            }
        }
        .sensoryFeedback(.success, trigger: createTick)
    }
}
