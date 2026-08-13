import SwiftUI

/// Admin panel (gap #12): users, jobs, libraries and API keys. Pushed from the
/// Me section (ProfileView) and only reachable when the current account is an
/// admin. No own NavigationStack (TrashView pattern).
struct AdminView: View {
    @Bindable var vm: AdminViewModel

    @State private var showCreateUser = false
    @State private var newUserName = ""
    @State private var newUserEmail = ""
    @State private var newUserPassword = ""
    @State private var newUserIsAdmin = false

    @State private var showCreateKey = false
    @State private var newKeyName = ""

    @State private var pendingDeleteUser: UserAdminResponseDto?
    @State private var pendingDeleteLibrary: LibraryResponseDto?

    var body: some View {
        Group {
            if vm.isLoading && vm.users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    usersSection
                    jobsSection
                    librariesSection
                    apiKeysSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load(force: true) }
        .alert("New User", isPresented: $showCreateUser) {
            TextField("Name", text: $newUserName)
            TextField("Email", text: $newUserEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            SecureField("Password", text: $newUserPassword)
            Toggle("Admin", isOn: $newUserIsAdmin)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await vm.createUser(name: newUserName, email: newUserEmail, password: newUserPassword, isAdmin: newUserIsAdmin) }
            }
        }
        .alert("New API Key", isPresented: $showCreateKey) {
            TextField("Name", text: $newKeyName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await vm.createAPIKey(name: newKeyName) }
            }
        }
        .alert("API Key Secret", isPresented: Binding(
            get: { vm.lastAPIKeySecret != nil },
            set: { if !$0 { vm.lastAPIKeySecret = nil } }
        )) {
            Button("Copy") { UIPasteboard.general.string = vm.lastAPIKeySecret }
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.lastAPIKeySecret ?? "")
        }
        .confirmationDialog(
            "Delete user?",
            isPresented: Binding(get: { pendingDeleteUser != nil }, set: { if !$0 { pendingDeleteUser = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete (force)", role: .destructive) {
                if let u = pendingDeleteUser { Task { await vm.deleteUser(u, force: true) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete library and all its assets?",
            isPresented: Binding(get: { pendingDeleteLibrary != nil }, set: { if !$0 { pendingDeleteLibrary = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let l = pendingDeleteLibrary { Task { await vm.deleteLibrary(l) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Users

    @ViewBuilder
    private var usersSection: some View {
        Section {
            ForEach(vm.users) { user in
                HStack(spacing: PVSpacing.s12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.pvBody)
                            .foregroundStyle(Color.textPrimaryPV)
                        Text(user.email)
                            .font(.pvCaption)
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                    Spacer()
                    if user.isAdmin == true {
                        Text("Admin")
                            .font(.pvCaption.weight(.semibold))
                            .foregroundStyle(Color.immichPrimary)
                    }
                }
                .contextMenu {
                    if user.deletedAt != nil {
                        Button {
                            Task { await vm.restoreUser(user) }
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button(role: .destructive) {
                        pendingDeleteUser = user
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                newUserName = ""
                newUserEmail = ""
                newUserPassword = ""
                newUserIsAdmin = false
                showCreateUser = true
            } label: {
                Label("Add user", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Users (\(vm.users.count))")
        }
    }

    // MARK: - Jobs

    @ViewBuilder
    private var jobsSection: some View {
        Section {
            ForEach(vm.sortedJobNames, id: \.self) { name in
                if let job = vm.jobs[name] {
                    HStack(spacing: PVSpacing.s12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.displayName(name))
                                .font(.pvBody)
                                .foregroundStyle(Color.textPrimaryPV)
                            Text(jobSummary(job))
                                .font(.pvCaption)
                                .foregroundStyle(Color.textSecondaryPV)
                        }
                        Spacer()
                        if job.queueStatus.isPaused {
                            Text("Paused")
                                .font(.pvCaption.weight(.semibold))
                                .foregroundStyle(Color.immichWarning)
                        } else if job.queueStatus.isActive {
                            Text("Active")
                                .font(.pvCaption.weight(.semibold))
                                .foregroundStyle(Color.immichSuccess)
                        }
                    }
                    .contextMenu {
                        Button { Task { await vm.runJob(name: name, command: "start") } } label: { Label("Run", systemImage: "play.fill") }
                        Button { Task { await vm.runJob(name: name, command: "pause") } } label: { Label("Pause", systemImage: "pause.fill") }
                        Button { Task { await vm.runJob(name: name, command: "resume") } } label: { Label("Resume", systemImage: "arrow.clockwise") }
                        Button { Task { await vm.runJob(name: name, command: "empty") } } label: { Label("Empty", systemImage: "trash") }
                        Button { Task { await vm.runJob(name: name, command: "clear-failed") } } label: { Label("Clear failed", systemImage: "xmark.circle") }
                    }
                }
            }
        } header: {
            Text("Jobs")
        }
    }

    // MARK: - Libraries

    @ViewBuilder
    private var librariesSection: some View {
        Section {
            ForEach(vm.libraries) { library in
                HStack(spacing: PVSpacing.s12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.name)
                            .font(.pvBody)
                            .foregroundStyle(Color.textPrimaryPV)
                        Text("\(library.assetCount ?? 0) assets")
                            .font(.pvCaption)
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                }
                .contextMenu {
                    Button {
                        Task { await vm.scanLibrary(library) }
                    } label: {
                        Label("Scan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        pendingDeleteLibrary = library
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Libraries (\(vm.libraries.count))")
        }
    }

    // MARK: - API keys

    @ViewBuilder
    private var apiKeysSection: some View {
        Section {
            ForEach(vm.apiKeys) { key in
                HStack(spacing: PVSpacing.s12) {
                    Text(key.name)
                        .font(.pvBody)
                        .foregroundStyle(Color.textPrimaryPV)
                    Spacer()
                    if let perms = key.permissions {
                        Text("\(perms.count) permissions")
                            .font(.pvCaption)
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await vm.deleteAPIKey(key) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                newKeyName = ""
                showCreateKey = true
            } label: {
                Label("Add API key", systemImage: "key")
            }
        } header: {
            Text("API Keys (\(vm.apiKeys.count))")
        }
    }

    // MARK: - Helpers

    private func jobSummary(_ job: QueueResponseLegacyDto) -> String {
        let c = job.jobCounts
        return "active \(c.active) · waiting \(c.waiting) · completed \(c.completed) · failed \(c.failed)"
    }

    private static func displayName(_ raw: String) -> String {
        raw.splitBeforeUppercase
    }
}

private extension String {
    /// "thumbnailGeneration" → "Thumbnail Generation"
    var splitBeforeUppercase: String {
        var out = ""
        for (i, ch) in self.enumerated() {
            if i > 0, ch.isUppercase {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.capitalized
    }
}
