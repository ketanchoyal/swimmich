import SwiftUI

/// "Moi" tab root (PRD §4).
///
/// Phase 0 scaffold: profile identity + relocation hub for the features that
/// lost their top-level tab in the PRD §4 restructure (Trash, Backup) + logout.
/// A full profile/settings screen (server, storage, about) is deferred.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @State var trash: TrashViewModel

    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.userName, let email = auth.userEmail {
                    Section {
                        LabeledContent("Name", value: user)
                        LabeledContent("Email", value: email)
                    } header: {
                        Text("Compte")
                    }
                }

                Section {
                    NavigationLink {
                        TrashView(vm: trash)
                    } label: {
                        Label("Corbeille", systemImage: "trash")
                    }

                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Sauvegarde", systemImage: "icloud.and.arrow.up")
                    }
                } header: {
                    Text("Gestion")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await auth.logout() }
                    } label: {
                        Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(auth.isLoading)
                }
            }
            .navigationTitle("Moi")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
