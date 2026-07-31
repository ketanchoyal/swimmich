import SwiftUI
import UIKit

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
    @State private var copiedLinkKey: String?
    @State private var pendingRevokeId: String?

    var body: some View {
        NavigationStack {
            List {
                createSection
                if !vm.sharedLinks.isEmpty {
                    existingSection
                }
            }
            .navigationTitle("Shared Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.loadSharedLinks() }
            .confirmationDialog(
                "Revoke this shared link?",
                isPresented: Binding(
                    get: { pendingRevokeId != nil },
                    set: { if !$0 { pendingRevokeId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Revoke", role: .destructive) {
                    if let id = pendingRevokeId {
                        Task { await vm.revokeSharedLink(id: id) }
                        pendingRevokeId = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingRevokeId = nil }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var createSection: some View {
        Section("New Link") {
            TextField("Description (optional)", text: $description)
            Toggle("Password protect", isOn: $usePassword)
            if usePassword {
                SecureField("Password", text: $password)
            }
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
        }
    }

    private var existingSection: some View {
        Section("Existing Links") {
            ForEach(vm.sharedLinks, id: \.id) { link in
                linkRow(link)
            }
        }
    }

    private func linkRow(_ link: SharedLinkResponseDto) -> some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            HStack {
                if link.password != nil {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.textSecondaryPV)
                }
                Text(link.description ?? "Untitled link")
                    .font(.pvSubhead)
                    .lineLimit(1)
            }
            HStack {
                Text(shareURL(for: link))
                    .font(.pvCaption).monospacedDigit()
                    .foregroundStyle(Color.textSecondaryPV)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = shareURL(for: link)
                    copiedLinkKey = link.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedLinkKey == link.id { copiedLinkKey = nil }
                    }
                } label: {
                    Image(systemName: copiedLinkKey == link.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    pendingRevokeId = link.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shareURL(for link: SharedLinkResponseDto) -> String {
        baseURL.appendingPathComponent("/share/\(link.key)").absoluteString
    }
}
