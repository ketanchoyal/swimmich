import SwiftUI

/// Shared-link management sheet for an album (AC-512, AC-513).
/// Create new link (optional password) + list/revoke existing links + copy URL.
///
/// `SharedLinkResponseDto.password` is the server-returned password string —
/// it is NEVER displayed in the UI (VM-J security). We only show a lock icon
/// when the link is password-protected.
struct SharedLinkSheet: View {
    @Bindable var vm: AlbumDetailViewModel
    let baseURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var usePassword = false
    @State private var password = ""
    @State private var pendingRevokeId: String?
    @State private var showRevokeConfirm = false
    @State private var editLinkItem: EditLinkItem?

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
            VStack(spacing: PVSpacing.s0) {
                TextField("Description (optional)", text: $description)
                    .padding(.horizontal, PVSpacing.s16)
                    .padding(.vertical, PVSpacing.s12)
                Divider()
                Toggle("Password protect", isOn: $usePassword)
                    .padding(.horizontal, PVSpacing.s16)
                    .padding(.vertical, PVSpacing.s8)
                if usePassword {
                    Divider()
                    SecureField("Password", text: $password)
                        .padding(.horizontal, PVSpacing.s16)
                        .padding(.vertical, PVSpacing.s12)
                }
                Divider()
                Button {
                    Task {
                        await vm.createSharedLink(
                            password: usePassword ? password : nil,
                            description: description.isEmpty ? nil : description
                        )
                        description = ""
                        password = ""
                        usePassword = false
                    }
                } label: {
                    Label("Create Link", systemImage: "square.and.arrow.up")
                }
                .disabled(vm.isLoading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PVSpacing.s16)
            }
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
                    baseURL: baseURL,
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
