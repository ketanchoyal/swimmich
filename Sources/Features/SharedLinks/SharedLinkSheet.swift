import SwiftUI

/// Shared-link management sheet for an album (AC-512, AC-513).
/// Create new link (optional password, custom slug, expiry) + list/revoke
/// existing links + copy URL.
///
/// `SharedLinkResponseDto.password` is the server-returned password string —
/// it is NEVER displayed in the UI (VM-J security). We only show a lock icon
/// when the link is password-protected.
struct SharedLinkSheet: View {
    @Bindable var vm: AlbumDetailViewModel
    @Environment(AuthViewModel.self) private var auth

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var usePassword = false
    @State private var password = ""
    @State private var slug = ""
    @State private var expiresAt: Date?
    @State private var pendingRevokeId: String?
    @State private var showRevokeConfirm = false
    @State private var editLinkItem: EditLinkItem?

    /// `externalDomain` when the server advertises one, the server URL
    /// otherwise — via the shared builder, so this sheet cannot drift from the
    /// Shared tab.
    private var sharedLinkBase: SharedLinkURL {
        SharedLinkURL(
            serverURL: auth.baseURL ?? URL(string: "https://example.com")!,
            externalDomain: auth.serverConfig?.externalDomain ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            List {
                createSection
                if !vm.sharedLinks.isEmpty {
                    existingSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Shared Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.loadSharedLinks() }
            .sheet(item: $editLinkItem) { item in
                EditSharedLinkSheet(link: item.link) { dto in
                    await vm.updateSharedLink(id: item.link.id, dto: dto)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Revoke this shared link?", isPresented: $showRevokeConfirm) {
                Button("Revoke", role: .destructive) {
                    if let id = pendingRevokeId {
                        Task { await vm.revokeSharedLink(id: id) }
                    }
                    withAnimation(PVMotion.snappy) {
                        pendingRevokeId = nil
                        showRevokeConfirm = false
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
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var createSection: some View {
        Section {
            // Three groups, one rule between each — the card pattern of
            // `ServerInfoCard`: the padding lives on the VStack, so every rule
            // is inset to the row content instead of spanning the card edge to
            // edge. A plain `Divider()` per row both ran full width (the rows
            // inset themselves, the divider did not) and one of them silently
            // never rendered — SwiftUI dropped the rule between the password
            // toggle and the custom-URL row — so the card's rhythm disagreed
            // with its own code. Grouping makes it deterministic.
            VStack(spacing: PVSpacing.s0) {
                TextField("Description (optional)", text: $description)
                    .padding(.vertical, PVSpacing.s12)

                Divider()

                // Options. One group on purpose: a toggle is not separated from
                // the field it reveals, and the slug and the expiry are the two
                // halves of the same setting (how the link is reached).
                Toggle("Password protect", isOn: $usePassword)
                    .padding(.vertical, PVSpacing.s8)
                if usePassword {
                    SecureField("Password", text: $password)
                        .padding(.vertical, PVSpacing.s12)
                }
                HStack(spacing: 0) {
                    if !slug.isEmpty {
                        Text("/s/")
                            .foregroundStyle(Color.textSecondaryPV)
                            .accessibilityHidden(true)
                    }
                    TextField("Custom URL", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("sharedLinkSlugField")
                }
                .padding(.vertical, PVSpacing.s12)

                SharedLinkExpiryPicker(date: $expiresAt)
                    .padding(.vertical, PVSpacing.s8)

                Divider()

                Button {
                    Task {
                        await vm.createSharedLink(
                            password: usePassword ? password : nil,
                            description: description.isEmpty ? nil : description,
                            slug: slug,
                            expiresAt: expiresAt
                        )
                        description = ""
                        password = ""
                        usePassword = false
                        slug = ""
                        expiresAt = nil
                    }
                } label: {
                    Label("Create Link", systemImage: "square.and.arrow.up")
                }
                .disabled(vm.isLoading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, PVSpacing.s16)
            }
            .padding(.horizontal, PVSpacing.s16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: PVSpacing.s4,
                leading: PVSpacing.s16,
                bottom: PVSpacing.s4,
                trailing: PVSpacing.s16
            ))
        } header: {
            Text("New Link")
        }
    }

    private var existingSection: some View {
        Section("Existing Links") {
            ForEach(vm.sharedLinks, id: \.id) { link in
                SharedLinkRow(
                    link: link,
                    sharedLinkBase: sharedLinkBase,
                    isPendingRevoke: pendingRevokeId == link.id,
                    onRevoke: { pendingRevokeId = link.id },
                    cardBackground: Color(uiColor: .systemBackground)
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
    }
}

#if DEBUG
// Layout review surface for this sheet — it is otherwise reachable only through
// a live album detail flow. Renders the "New Link" card plus one existing link.
#Preview("Shared link sheet") {
    let vm = AlbumDetailViewModel(client: DependencyContainer.shared.client, albumId: "preview")
    vm.sharedLinks = [
        SharedLinkResponseDto(
            id: "link-1", description: "Trip", password: nil, userId: "owner", key: "a2V5",
            type: .album, createdAt: "2026-01-01T00:00:00.000Z", expiresAt: nil,
            assets: [], album: nil, allowUpload: false, allowDownload: true,
            showMetadata: true, slug: "trip-2026"
        )
    ]
    return SharedLinkSheet(vm: vm)
        .environment(DependencyContainer.shared.makeAuthViewModel())
}
#endif
