import SwiftUI

/// "API Keys" (gap G20): the keys of the account that is signed in, reached from
/// the Me hub by every account — administrator or not. The admin console used to
/// own this list behind `if auth.isAdmin`, which is exactly the gap this screen
/// closes; it is now the only owner of the surface.
///
/// No `NavigationStack` of its own: the Me hub pushes it inside the stack it
/// already owns (OfflineAssetsView pattern).
struct UserApiKeysView: View {
    @Bindable var vm: UserApiKeysViewModel

    @State private var showCreate = false

    var body: some View {
        List {
            // Informative only — it says which key signs the calls that bear it,
            // and carries no gesture: rotation and revocation belong to the
            // "Your keys" rows, where the object is chosen.
            if let myKey = vm.myKey {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(myKey.name)
                            .font(.pvBody)
                            .foregroundStyle(Color.textPrimaryPV)
                        Text(vm.permissionsSummary(myKey))
                            .font(.pvCaption)
                            .foregroundStyle(Color.textTertiaryPV)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("apiKeysCurrentRow")
                } header: {
                    Text("Current session")
                }
            }

            Section {
                if vm.keys.isEmpty && !vm.isLoading {
                    ContentUnavailableView("No API keys yet", systemImage: "key.horizontal")
                }
                ForEach(vm.keys) { key in
                    keyRow(key)
                }
            } header: {
                Text("Your keys")
            }

            // Loading and transport failures never take the screen over: the
            // list stays usable and the message renders in context.
            if let message = vm.errorMessage {
                Section {
                    InlineErrorBadge(message: message)
                }
            }
        }
        .overlay {
            if vm.isLoading && vm.keys.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .accessibilityIdentifier("apiKeysCreateButton")
            }
        }
        .task {
            await vm.load()
            await vm.loadMyKey()
        }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showCreate) {
            APIKeyCreateView { name, permissions in
                await vm.create(name: name, permissions: permissions)
            }
        }
        // The ONE place a secret is ever shown, for a creation as much as for a
        // rotation: `pendingSecret` is cleared when this closes, and no other
        // surface keeps a copy.
        .alert("API Key Secret", isPresented: Binding(
            get: { vm.pendingSecret != nil },
            set: { if !$0 { vm.dismissSecret() } }
        )) {
            Button("Copy") { UIPasteboard.general.string = vm.pendingSecret }
                .accessibilityIdentifier("apiKeyCopySecretButton")
            Button("OK", role: .cancel) { vm.dismissSecret() }
        } message: {
            Text(vm.pendingSecret ?? "")
        }
        .confirmationDialog(
            "Rotate key?",
            isPresented: Binding(
                get: { vm.rotationTarget != nil },
                set: { if !$0 { vm.rotationTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Rotate") {
                if let key = vm.rotationTarget { Task { await vm.rotate(key) } }
            }
            .accessibilityIdentifier("apiKeyRotateConfirmButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current secret stops working immediately. The new secret is shown once.")
        }
        .confirmationDialog(
            "Delete key?",
            isPresented: Binding(
                get: { vm.deletionTarget != nil },
                set: { if !$0 { vm.deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let key = vm.deletionTarget { Task { await vm.delete(key) } }
            }
            .accessibilityIdentifier("apiKeyDeleteConfirmButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apps using this key will stop working.")
        }
    }

    /// One owned key: name, creation date and the scope it carries. Both
    /// gestures only *designate* the key — the mutation waits for the dialog.
    @ViewBuilder
    private func keyRow(_ key: ApiKeyResponseDto) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.name)
                .font(.pvBody)
                .foregroundStyle(Color.textPrimaryPV)
            Text(vm.formattedCreatedAt(key))
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
            Text(vm.permissionsSummary(key))
                .font(.pvCaption)
                .foregroundStyle(Color.textTertiaryPV)
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.deletionTarget = key
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                vm.rotationTarget = key
            } label: {
                Label("Rotate", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }
}
