import SwiftUI

/// Profile identity + relocation hub for the features that lost their top-level
/// tab in the PRD §4 restructure (Trash, Backup) + logout. Since P1
/// storage-stats, also shows the server's storage usage + quota.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLockViewModel.self) private var appLock
    @AppStorage(AppLockViewModel.enabledKey) private var appLockEnabled = false
    @Environment(\.openURL) private var openURL
    @State var trash: TrashViewModel
    @State var storage: StorageStatsViewModel
    @State var upload: UploadViewModel
    @State var uploadDetail: UploadDetailViewModel
    @State var duplicates: DuplicatesViewModel
    @State var people: PeopleViewModel
    @State var tags: TagsViewModel
    @State var stacks: StacksViewModel
    @State var partners: PartnersViewModel
    @State var admin: AdminViewModel
    @State var offline: OfflineDownloadViewModel
    @State var syncStatus: SyncStatusViewModel
    @State var notifications: NotificationsViewModel
    @State var language: LanguageSettingsViewModel
    @State var localLibrary: LocalLibraryViewModel
    @State var freeUpSpace: FreeUpSpaceViewModel

    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.userName, let email = auth.userEmail {
                    Section {
                        LabeledContent("Name", value: user)
                        LabeledContent("Email", value: email)
                    } header: {
                        Text("Account")
                    }
                }

                serversSection

                webSection

                storageSection

                // Language sits on its own rather than in Management: it is a
                // device-level choice like Security, not another library screen.
                Section {
                    NavigationLink {
                        LanguageSettingsView(vm: language)
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    .accessibilityIdentifier("languageRow")
                } header: {
                    Text("General")
                }

                Section {
                    NavigationLink {
                        TrashView(vm: trash)
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }

                    NavigationLink {
                        BackupSettingsView(vm: upload, detail: uploadDetail)
                    } label: {
                        Label("Backup", systemImage: "icloud.and.arrow.up")
                    }

                    // Right after Backup: this screen reads the ledger that
                    // screen feeds.
                    NavigationLink {
                        SyncStatusView(vm: syncStatus)
                    } label: {
                        Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("syncStatusRow")

                    // Next to Backup on purpose: the only notification this app
                    // posts is the end of a backup run.
                    NavigationLink {
                        NotificationSettingsView(vm: notifications)
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("notificationsRow")

                    NavigationLink {
                        DuplicatesView(vm: duplicates)
                    } label: {
                        Label("Duplicates", systemImage: "rectangle.on.rectangle.angled")
                    }

                    NavigationLink {
                        PeopleView(vm: people)
                    } label: {
                        Label("People", systemImage: "person.2")
                    }

                    NavigationLink {
                        TagsView(vm: tags)
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }

                    NavigationLink {
                        StackView(vm: stacks)
                    } label: {
                        Label("Stacks", systemImage: "square.stack.3d.down.right")
                    }

                    NavigationLink {
                        PartnersView(vm: partners)
                    } label: {
                        Label("Partners", systemImage: "person.badge.plus")
                    }

                    NavigationLink {
                        OfflineAssetsView(vm: offline)
                    } label: {
                        Label("Offline Storage", systemImage: "arrow.down.circle")
                    }
                    .accessibilityIdentifier("offlineStorageRow")

                    // Next to Offline Storage on purpose: both lines read the
                    // device, not the server.
                    NavigationLink {
                        LocalLibraryView(vm: localLibrary)
                    } label: {
                        Label("On this device", systemImage: "iphone")
                    }
                    .accessibilityIdentifier("localLibraryRow")
                    // Last in Management on purpose: it acts on what the DEVICE
                    // holds, like the Offline Storage row right above, and keeps
                    // the Backup / Sync cluster (what goes up) intact.
                    NavigationLink {
                        FreeUpSpaceView(vm: freeUpSpace)
                    } label: {
                        Label("Free Up Space", systemImage: "externaldrive.badge.minus")
                    }
                    .accessibilityIdentifier("freeUpSpaceRow")
                } header: {
                    Text("Management")
                }

                if auth.isAdmin {
                    Section {
                        NavigationLink {
                            AdminView(vm: admin)
                        } label: {
                            Label("Administration", systemImage: "gearshape.2")
                        }
                    } header: {
                        Text("Administration")
                    }
                }

                // App lock lives here rather than on the Backup screen: it
                // guards the whole app, not the backup run.
                Section {
                    Toggle("Require Face ID", isOn: $appLockEnabled)
                        .onChange(of: appLockEnabled) { _, newValue in
                            appLock.setEnabled(newValue)
                        }
                        .accessibilityIdentifier("appLockToggle")
                } header: {
                    Text("Security")
                } footer: {
                    Text("Asks for Face ID (or your passcode) every time Immich comes back to the foreground, so someone holding your unlocked phone can't browse your photos.")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await auth.logout() }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(auth.isLoading)
                }
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.inline)
            .task { await storage.load() }
            .refreshable { await storage.load() }
        }
    }

    /// Saved accounts / servers (P5 multi-server): tap to switch, swipe to
    /// remove, or add a brand-new account.
    @ViewBuilder
    private var serversSection: some View {
        Section {
            ForEach(auth.savedAccounts) { account in
                Button {
                    Task { await auth.switchToAccount(account) }
                } label: {
                    HStack(spacing: PVSpacing.s8) {
                        Label(account.name ?? account.url, systemImage: "server.rack")
                            .foregroundStyle(.primary)
                        Spacer()
                        if account.id == auth.activeAccountID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.immichPrimary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    auth.removeSavedAccount(auth.savedAccounts[index])
                }
            }

            Button {
                auth.addNewServer()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        } header: {
            Text("Servers")
        }
    }

    /// Open the Immich web UI of the active server in the browser (gap #9).
    @ViewBuilder
    private var webSection: some View {
        Section {
            Button {
                if let url = auth.baseURL { openURL(url) }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .disabled(auth.baseURL == nil)
        } header: {
            Text("Server")
        }
    }

    /// Server storage usage (P1 storage-stats): photo/video counts, total
    /// bytes used and, when the server defines a quota, a determinate bar.
    @ViewBuilder
    private var storageSection: some View {
        Section {
            LabeledContent("Photos", value: storage.photos.formatted())
            LabeledContent("Videos", value: storage.videos.formatted())
            LabeledContent("Usage", value: StorageStatsViewModel.format(storage.usage))
            if let quota = storage.quotaSizeInBytes, quota > 0 {
                ProgressView(
                    value: min(Double(storage.usage) / Double(quota), 1.0)
                )
                LabeledContent("Quota", value: StorageStatsViewModel.format(quota))
            }
            if storage.isLoading {
                HStack(spacing: PVSpacing.s8) {
                    ProgressView()
                    Text("Loading…")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
            } else if let error = storage.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichError)
            }
        } header: {
            Text("Storage")
        }
    }
}
