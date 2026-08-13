import SwiftUI

/// Profile identity + relocation hub for the features that lost their top-level
/// tab in the PRD §4 restructure (Trash, Backup) + logout. Since P1
/// storage-stats, also shows the server's storage usage + quota.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @State var trash: TrashViewModel
    @State var storage: StorageStatsViewModel

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

                storageSection

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
            .task { await storage.load() }
            .refreshable { await storage.load() }
        }
    }

    /// Server storage usage (P1 storage-stats): photo/video counts, total
    /// bytes used and, when the server defines a quota, a determinate bar.
    @ViewBuilder
    private var storageSection: some View {
        Section {
            LabeledContent("Photos", value: storage.photos.formatted())
            LabeledContent("Vidéos", value: storage.videos.formatted())
            LabeledContent("Utilisation", value: StorageStatsViewModel.format(storage.usage))
            if let quota = storage.quotaSizeInBytes, quota > 0 {
                ProgressView(
                    value: min(Double(storage.usage) / Double(quota), 1.0)
                )
                LabeledContent("Quota", value: StorageStatsViewModel.format(quota))
            }
            if storage.isLoading {
                HStack(spacing: PVSpacing.s8) {
                    ProgressView()
                    Text("Chargement…")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
            } else if let error = storage.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichError)
            }
        } header: {
            Text("Stockage")
        }
    }
}
