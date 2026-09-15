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
    @State var recentTaken: RecentAssetsViewModel
    @State var recentAdded: RecentAssetsViewModel
    @State var syncStatus: SyncStatusViewModel
    @State var notifications: NotificationsViewModel
    @State var language: LanguageSettingsViewModel
    /// Connected devices (gap G19). Built by the composition root and owned by
    /// `RootView`, so the pushed screen and its row share one instance.
    @State var deviceSessions: DeviceSessionsViewModel
    @State var localLibrary: LocalLibraryViewModel
    @State var freeUpSpace: FreeUpSpaceViewModel
    @State var folders: FolderViewModel
    /// Profile picture screen (gap G16). Built by the composition root and owned
    /// by `RootView`, so the row below and the pushed screen show one photo.
    @State var profilePicture: ProfilePictureViewModel
    /// Locked folder (gap G12). A plain `let`, not a `@State`: the ViewModel's
    /// lifetime is the Me sheet's (`AuthenticatedRoot` owns it), so re-entering
    /// the row does not reset a folder the user is working in.
    let lockedFolder: LockedFolderViewModel
    /// Change-password screen (gap G18). Built by the composition root: the
    /// screen is pushed, so the row and the form must show one instance.
    @State var changePassword: ChangePasswordViewModel
    /// User API keys (gap G20). A `@State`, like the hub's other ViewModels: the
    /// sheet's lifetime is its owner's.
    @State var apiKeys: UserApiKeysViewModel

    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.userName, let email = auth.userEmail {
                    Section {
                        NavigationLink {
                            ProfilePictureView(vm: profilePicture)
                        } label: {
                            profilePictureRow
                        }
                        .accessibilityIdentifier("profilePictureRow")

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

                // Consultation, not configuration: two read-only grids over the
                // library sit above Management, which carries settings. Pushed
                // without a stack — this view already owns one.
                Section {
                    NavigationLink {
                        RecentAssetsView(vm: recentTaken)
                    } label: {
                        Label("Recently Taken", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("recentTakenRow")

                    NavigationLink {
                        RecentAssetsView(vm: recentAdded)
                    } label: {
                        Label("Recently Added", systemImage: "arrow.up.circle")
                    }
                    .accessibilityIdentifier("recentAddedRow")
                } header: {
                    Text("Recently")
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

                    // Next to Offline Storage on purpose: the two lines read the
                    // same library from its two sides — what the device keeps in
                    // cache, and the tree the server sees on its disk.
                    NavigationLink {
                        FolderView(vm: folders, node: nil)
                    } label: {
                        Label("Folders", systemImage: "folder")
                    }
                    .accessibilityIdentifier("foldersRow")

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

                    // Last in Management, and deliberately OUTSIDE the admin-only
                    // section below: the list endpoint is scoped to the bearer of
                    // the token, so every account manages its own keys here
                    // (gap G20).
                    NavigationLink {
                        UserApiKeysView(vm: apiKeys)
                    } label: {
                        Label("API Keys", systemImage: "key.horizontal")
                    }
                    .accessibilityIdentifier("apiKeysRow")
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
                    // The locked folder is a place, the toggle below is a
                    // setting: a row, not a switch — and it comes first because
                    // it is the narrower protection (one folder vs the app).
                    NavigationLink {
                        LockedFolderView(vm: lockedFolder)
                    } label: {
                        Label("Locked Folder", systemImage: "lock")
                    }
                    .accessibilityIdentifier("lockedFolderRow")

                    // Above the toggle on purpose: this row answers a
                    // server-side request about the account itself, where the
                    // toggle below is a setting of this device.
                    NavigationLink {
                        ChangePasswordView(vm: changePassword, onPasswordChanged: { auth.notePasswordChanged() })
                    } label: {
                        Label("Change Password", systemImage: "key")
                    }
                    .accessibilityIdentifier("changePasswordRow")

                    // The server's own signal that an administrator reset this
                    // account's password: an invitation, not a wall — the row
                    // above stays the only way in, and nothing is gated on it.
                    if auth.shouldChangePassword {
                        Label("This server asks you to change your password.", systemImage: "exclamationmark.triangle.fill")
                            .font(.pvCaption)
                            .foregroundStyle(Color.immichWarning)
                            .accessibilityIdentifier("shouldChangePasswordNotice")
                    }

                    Toggle("Require Face ID", isOn: $appLockEnabled)
                        .onChange(of: appLockEnabled) { _, newValue in
                            appLock.setEnabled(newValue)
                        }
                        .accessibilityIdentifier("appLockToggle")

                    // After the app lock, before the logout button: sessions are
                    // a security object, not a library screen — and this row
                    // signs other devices out, which is what "Log Out" below
                    // deliberately cannot do.
                    NavigationLink {
                        DeviceSessionsView(vm: deviceSessions)
                    } label: {
                        Label("Connected Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    .accessibilityIdentifier("deviceSessionsRow")
                } header: {
                    Text("Security")
                } footer: {
                    Text("Asks for Face ID (or your passcode) every time Immich comes back to the foreground, so someone holding your unlocked phone can't browse your photos.")
                    Text("Photos in the locked folder are hidden everywhere else and open with your Immich PIN — a separate code from this app lock.")
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
            // The flag is a server fact, not a login-only event: re-read it
            // here so a password reset that happened mid-session still shows.
            .task { await auth.refreshShouldChangePassword() }
            // The Account row carries the avatar, so the identity has to be
            // known before the screen that publishes the photo is opened.
            .task { await profilePicture.load() }
            .refreshable { await storage.load() }
        }
    }

    /// Account row for the profile picture (gap G16). It carries the avatar on
    /// purpose: a plain label would promise a photo the hub never shows.
    @ViewBuilder
    private var profilePictureRow: some View {
        HStack(spacing: PVSpacing.s12) {
            if let user = profilePicture.avatarUser {
                UserAvatarCircle(user: user, size: 40, baseURL: auth.baseURL, token: auth.accessToken)
            } else {
                // Identity still in flight (or unreachable): keep the row's
                // height and let the avatar arrive rather than jump.
                Circle()
                    .fill(Color.bgTertiary)
                    .frame(width: 40, height: 40)
            }
            Text("Profile Picture")
                .font(.pvBody)
                .foregroundStyle(Color.textPrimaryPV)
        }
        .frame(minHeight: 44)
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
