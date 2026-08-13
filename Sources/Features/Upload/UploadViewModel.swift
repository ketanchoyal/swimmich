import Foundation
import SwiftUI

/// Persisted backup preferences, stored in an injectable UserDefaults suite
/// ("backupSettings" in production, per-test suites in unit tests).
@Observable
@MainActor
final class BackupSettingsStore {
    @ObservationIgnored let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    var onlyOnWiFi: Bool {
        didSet { defaults.set(onlyOnWiFi, forKey: Self.wifiKey) }
    }

    var onlyWhenCharging: Bool {
        didSet { defaults.set(onlyWhenCharging, forKey: Self.chargingKey) }
    }

    var excludeScreenshots: Bool {
        didSet { defaults.set(excludeScreenshots, forKey: Self.screenshotsKey) }
    }

    var selectedAlbumIDs: Set<String> {
        didSet { defaults.set(Array(selectedAlbumIDs), forKey: Self.albumsKey) }
    }

    static let enabledKey = "photoBackupEnabled"
    static let wifiKey = "photoBackupOnlyWiFi"
    static let chargingKey = "photoBackupOnlyCharging"
    static let screenshotsKey = "photoBackupExcludeScreenshots"
    static let albumsKey = "photoBackupSelectedAlbums"

    init(suiteName: String = "backupSettings") {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        onlyOnWiFi = defaults.bool(forKey: Self.wifiKey)
        onlyWhenCharging = defaults.bool(forKey: Self.chargingKey)
        excludeScreenshots = defaults.bool(forKey: Self.screenshotsKey)
        selectedAlbumIDs = Set(defaults.stringArray(forKey: Self.albumsKey) ?? [])
    }

    /// Snapshot the current prefs; the engine runs against a frozen copy.
    func snapshot() -> BackupSettings {
        BackupSettings(
            isEnabled: isEnabled,
            onlyOnWiFi: onlyOnWiFi,
            onlyWhenCharging: onlyWhenCharging,
            excludeScreenshots: excludeScreenshots,
            selectedAlbumIDs: selectedAlbumIDs
        )
    }
}

/// Upload / backup view model — thin glue between the engine, the settings
/// store and the scheduler. The testable logic lives in `BackupEngine`.
@Observable
@MainActor
final class UploadViewModel {
    let client: any ImmichClient
    let photos: any PhotoLibraryService
    let engine: BackupEngine
    var settings: BackupSettingsStore
    let scheduler: any BackgroundBackupScheduling

    var albums: [BackupAlbum] = []

    init(
        client: any ImmichClient,
        photos: any PhotoLibraryService,
        engine: BackupEngine? = nil,
        settings: BackupSettingsStore? = nil,
        scheduler: any BackgroundBackupScheduling = BGTaskBackupScheduler()
    ) {
        self.client = client
        self.photos = photos
        self.engine = engine ?? BackupEngine(
            client: client,
            source: (photos as? BackupAssetSource) ?? PhotoLibraryServiceImpl()
        )
        self.settings = settings ?? BackupSettingsStore()
        self.scheduler = scheduler
    }

    var running: Bool {
        engine.phase == .checking || engine.phase == .uploading
    }

    func runBackup() async {
        await engine.run(settings: settings.snapshot())
        if engine.phase == .done {
            scheduler.submit()
        }
    }

    func cancelBackup() {
        engine.cancel()
    }

    func loadAlbums() {
        albums = engine.source.fetchAlbums()
    }
}

/// Backup settings screen — the real backup UI (was a scaffold).
struct BackupSettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLockViewModel.self) private var appLock
    @AppStorage("app_lock_enabled") private var appLockEnabled = false

    @State var vm: UploadViewModel

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server", value: auth.serverURLString)
                    LabeledContent("User", value: auth.userEmail ?? "—")
                }
                backupSection
                progressSection
                // AC-114: Require Face ID toggle. @AppStorage mirrors the
                // same UserDefaults key AppLockViewModel reads, and onChange
                // keeps the VM's stored isEnabled in sync.
                Section("Security") {
                    Toggle("Require Face ID", isOn: $appLockEnabled)
                        .onChange(of: appLockEnabled) { _, newValue in
                            appLock.setEnabled(newValue)
                        }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ImmichAppBar(title: "Backup")
                }
            }
            .task {
                vm.loadAlbums()
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        @Bindable var vm = vm
        Section("Auto backup") {
            Toggle("Auto backup", isOn: $vm.settings.isEnabled)
                .onChange(of: vm.settings.isEnabled) { _, newValue in
                    Task {
                        if newValue {
                            vm.photos.requestAuthorization { status in
                                Task { @MainActor in
                                    if status == .authorized || status == .limited {
                                        vm.scheduler.submit()
                                    }
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("autoBackupToggle")
            Toggle("Wi-Fi only", isOn: $vm.settings.onlyOnWiFi)
            Toggle("Charging only", isOn: $vm.settings.onlyWhenCharging)
            Toggle("Exclude screenshots", isOn: $vm.settings.excludeScreenshots)
            NavigationLink {
                AlbumPickerView(albums: vm.albums, settings: vm.settings)
            } label: {
                LabeledContent("Albums", value: vm.settings.selectedAlbumIDs.isEmpty
                               ? "All"
                               : "\(vm.settings.selectedAlbumIDs.count) selected")
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Section("Progress") {
            if vm.running {
                ProgressView(
                    value: Double(vm.engine.currentIndex),
                    total: max(1, Double(vm.engine.total))
                )
            }
            if vm.engine.phase != .idle {
                LabeledContent("Uploaded", value: String(vm.engine.uploadedCount))
                LabeledContent("Already on server", value: String(vm.engine.rejectedCount))
                LabeledContent("Failed", value: String(vm.engine.failedCount))
            }
            Button {
                Task { await vm.runBackup() }
            } label: {
                Label(vm.running ? "Backing up…" : "Run now", systemImage: "arrow.up.circle")
            }
            .disabled(vm.running)
            .accessibilityIdentifier("runBackupButton")
            if vm.running {
                Button("Cancel", role: .destructive) {
                    vm.cancelBackup()
                }
                .accessibilityIdentifier("cancelBackupButton")
            }
            if let error = vm.engine.lastError {
                Text(error)
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichError)
            }
        }
    }
}

/// Album selection list — checkmarks bind into the persisted store.
struct AlbumPickerView: View {
    let albums: [BackupAlbum]
    @Bindable var settings: BackupSettingsStore

    var body: some View {
        List {
            if albums.isEmpty {
                Text("No albums")
                    .font(.pvCaption)
                    .foregroundStyle(Color.textSecondaryPV)
            } else {
                ForEach(albums) { album in
                    Button {
                        if settings.selectedAlbumIDs.contains(album.id) {
                            settings.selectedAlbumIDs.remove(album.id)
                        } else {
                            settings.selectedAlbumIDs.insert(album.id)
                        }
                    } label: {
                        HStack {
                            Text(album.name)
                                .foregroundStyle(Color.textPrimaryPV)
                            Spacer()
                            if settings.selectedAlbumIDs.contains(album.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.immichPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}
