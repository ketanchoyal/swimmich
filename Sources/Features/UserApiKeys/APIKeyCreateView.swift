import SwiftUI

/// The create sheet: a name and a permission scope, transposed from the web
/// app's user-settings selector (one dropdown per category, a state-wide
/// "select all" inside it, and one switch per permission).
///
/// It declares its own `NavigationStack` because a sheet inherits no bar at all:
/// without it, `Create` and `Cancel` would have nowhere to live.
///
/// The sheet never sees the secret. `onCreate` answers whether a key was made,
/// and the secret itself is shown by the one alert `UserApiKeysView` owns — two
/// surfaces rendering a one-shot secret is how one of them ends up diverging.
struct APIKeyCreateView: View {
    let onCreate: (String, [String]) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var fullAccess = true
    @State private var selected: Set<String> = []
    @State private var expanded: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("apiKeyNameField")
                }

                Section {
                    Toggle("Full access", isOn: $fullAccess)
                        .accessibilityIdentifier("apiKeyFullAccessToggle")
                }

                // The 168 server permissions are unreadable as one flat list,
                // so each category starts folded. The selection itself survives
                // folding and switching "Full access" off and on again.
                if !fullAccess {
                    Section {
                        ForEach(APIKeyPermission.grouped, id: \.category) { group in
                            DisclosureGroup(isExpanded: expansion(of: group.category)) {
                                Button(allSelected(group.items) ? "Deselect all" : "Select all") {
                                    toggleAll(group.items)
                                }
                                .accessibilityIdentifier("apiKeyCategoryToggle_\(group.category)")

                                ForEach(group.items, id: \.self) { permission in
                                    Toggle(permission, isOn: selection(of: permission))
                                        .accessibilityIdentifier("apiKeyPermissionToggle_\(permission)")
                                }
                            } label: {
                                LabeledContent(
                                    group.category,
                                    value: "\(group.items.filter { selected.contains($0) }.count)/\(group.items.count)"
                                )
                            }
                        }
                    } header: {
                        Text("Permissions")
                    }
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            // Closed only on success: a rejected name keeps the
                            // sheet (and what the user typed) on screen.
                            if await onCreate(name, fullAccess ? [APIKeyPermission.allPermission] : Array(selected)) {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("apiKeyCreateConfirmButton")
                }
            }
        }
    }

    // MARK: - Selection

    private func selection(of permission: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(permission) },
            set: { isOn in
                if isOn { selected.insert(permission) } else { selected.remove(permission) }
            }
        )
    }

    private func expansion(of category: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(category) },
            set: { isExpanded in
                if isExpanded { expanded.insert(category) } else { expanded.remove(category) }
            }
        )
    }

    private func allSelected(_ items: [String]) -> Bool {
        items.allSatisfy { selected.contains($0) }
    }

    private func toggleAll(_ items: [String]) {
        if allSelected(items) {
            selected.subtract(items)
        } else {
            selected.formUnion(items)
        }
    }
}
