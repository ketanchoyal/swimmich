import Foundation
import Photos
import SwiftUI
import UIKit

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

    var excludeCameraRoll: Bool {
        didSet { defaults.set(excludeCameraRoll, forKey: Self.excludeCameraRollKey) }
    }

    var excludeWhatsApp: Bool {
        didSet { defaults.set(excludeWhatsApp, forKey: Self.excludeWhatsAppKey) }
    }

    var autoDetectNewPhotos: Bool {
        didSet { defaults.set(autoDetectNewPhotos, forKey: Self.autoDetectNewPhotosKey) }
    }

    var selectedAlbumIDs: Set<String> {
        didSet { defaults.set(Array(selectedAlbumIDs), forKey: Self.albumsKey) }
    }

    static let enabledKey = "photoBackupEnabled"
    static let wifiKey = "photoBackupOnlyWiFi"
    static let chargingKey = "photoBackupOnlyCharging"
    static let screenshotsKey = "photoBackupExcludeScreenshots"
    static let albumsKey = "photoBackupSelectedAlbums"
    static let excludeCameraRollKey = "photoBackupExcludeCameraRoll"
    static let excludeWhatsAppKey = "photoBackupExcludeWhatsApp"
    static let autoDetectNewPhotosKey = "photoBackupAutoDetectNewPhotos"

    init(suiteName: String = "backupSettings") {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        onlyOnWiFi = defaults.bool(forKey: Self.wifiKey)
        onlyWhenCharging = defaults.bool(forKey: Self.chargingKey)
        excludeScreenshots = defaults.bool(forKey: Self.screenshotsKey)
        excludeCameraRoll = defaults.bool(forKey: Self.excludeCameraRollKey)
        excludeWhatsApp = defaults.bool(forKey: Self.excludeWhatsAppKey)
        autoDetectNewPhotos = defaults.bool(forKey: Self.autoDetectNewPhotosKey)
        selectedAlbumIDs = Set(defaults.stringArray(forKey: Self.albumsKey) ?? [])
    }

    /// Snapshot the current prefs; the engine runs against a frozen copy.
    func snapshot() -> BackupSettings {
        BackupSettings(
            isEnabled: isEnabled,
            excludeCameraRoll: excludeCameraRoll,
            excludeWhatsApp: excludeWhatsApp,
            autoDetectNewPhotos: autoDetectNewPhotos,
            onlyOnWiFi: onlyOnWiFi,
            onlyWhenCharging: onlyWhenCharging,
            excludeScreenshots: excludeScreenshots,
            selectedAlbumIDs: selectedAlbumIDs
        )
    }
}

/// Upload / backup view model — thin glue between the engine, the settings
/// store and the scheduler. The testable logic lives in `BackupEngine`.

/// Record of a completed backup run for upload history display.
struct UploadHistoryEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    let uploaded: Int
    let total: Int
    let failed: Int
    let success: Bool
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
    let activityService: any BackupLiveActivityServicing
    let notifications: any BackupNotificationServicing

    var albums: [BackupAlbum] = []

    // Resume state
    var canResume: Bool {
        engine.phase == .done || engine.phase == .cancelled
    }

    // Backfill + history
    var showBackfillSheet: Bool = false
    var uploadHistory: [UploadHistoryEntry] = []
    var lastBackupResult: (uploaded: Int, total: Int, failed: Int)?

    /// Handle to the in-flight backup started by `resumeUpload`/`runBackfill`
    /// (which must return immediately for the UI). Lets callers/tests await it.
    @ObservationIgnored private(set) var currentBackupTask: Task<Void, Never>?

    init(
        client: any ImmichClient,
        photos: any PhotoLibraryService,
        engine: BackupEngine? = nil,
        settings: BackupSettingsStore? = nil,
        scheduler: any BackgroundBackupScheduling = BGTaskBackupScheduler(),
        activityService: any BackupLiveActivityServicing = LiveActivityBackupService(),
        notifications: any BackupNotificationServicing = BackupNotificationService()
    ) {
        self.client = client
        self.photos = photos
        self.engine = engine ?? BackupEngine(
            client: client,
            source: (photos as? BackupAssetSource) ?? PhotoLibraryServiceImpl()
        )
        self.settings = settings ?? BackupSettingsStore()
        self.scheduler = scheduler
        self.activityService = activityService
        self.notifications = notifications
    }

    var running: Bool {
        engine.phase == .checking || engine.phase == .uploading
    }

    /// Requests Photos read access. Returns true once authorized/limited.
    /// Manual runs call this first — without it `fetchCandidates` silently
    /// returns nothing and the run "does nothing".
    private func ensurePhotoAccess() async -> Bool {
        let status = photos.authorizationStatus()
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                photos.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            return false
        }
    }

    /// Photo access with a user-visible consequence: prompts when not
    /// determined; sends the user to the system settings when denied, so a
    /// silently-dead "Auto backup" toggle is impossible (the previous
    /// behavior: requestAuthorization resolves denied → no submit → the
    /// automatic chain never starts, no error shown anywhere).
    func requestPhotoAccessThenOpenDenied() {
        let status = photos.authorizationStatus()
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            photos.requestAuthorization { status in
                Task { @MainActor in
                    if status == .denied || status == .restricted {
                        self.openPhotoSettings()
                    }
                }
            }
        default:
            openPhotoSettings()
        }
    }

    private func openPhotoSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Runs the backup. `manual` (Run now / resume / backfill / retry)
    /// bypasses the automatic gates and first secures Photos access; the
    /// unattended BGTask path passes `manual: false`.
    func runBackup(overrideSettings: BackupSettings? = nil, manual: Bool = false) async {
        if manual {
            guard await ensurePhotoAccess() else {
                engine.reportError("Photo library access is required to back up.")
                return
            }
        }
        notifications.requestAuthorization()
        engine.onProgressUpdate = { [weak self] uploaded, total in
            self?.activityService.update(uploaded: uploaded, total: total)
        }
        activityService.start(uploaded: 0, total: 0)
        await engine.run(settings: overrideSettings ?? settings.snapshot(), manual: manual)
        engine.onProgressUpdate = nil
        switch engine.phase {
        case .done:
            let success = engine.failedCount == 0
            activityService.end(uploaded: engine.uploadedCount, total: engine.total, success: success)
            notifications.notifyBackupComplete(
                uploaded: engine.uploadedCount,
                total: engine.total,
                failed: engine.failedCount,
                success: success
            )
            // Keeps the automatic chain self-perpetuating while auto-backup
            // is on — including after a manual run, which heals a chain the
            // OS dropped (e.g. the process was killed mid-window).
            if settings.isEnabled {
                scheduler.submit()
            }
            // Record history
            uploadHistory.append(UploadHistoryEntry(
                date: Date(),
                uploaded: engine.uploadedCount,
                total: engine.total,
                failed: engine.failedCount,
                success: success
            ))
            lastBackupResult = (engine.uploadedCount, engine.total, engine.failedCount)
            // Keep last 10 entries
            if uploadHistory.count > 10 {
                uploadHistory = uploadHistory.suffix(10)
            }
        case .cancelled:
            activityService.end(uploaded: engine.uploadedCount, total: engine.total, success: false)
        default:
            break
        }
    }

    func cancelBackup() {
        engine.cancel()
    }


    /// Foreground-triggered automatic pass — the "Auto-detect new photos"
    /// behavior: on every scene activation, run a (gated) scan when the
    /// user opted in. The run is NOT manual: Wi-Fi-only / charging-only
    /// still apply. When the toggle is off, only the OS background window
    /// triggers runs (the pending request is kept alive on activation).
    func kickOffAutoBackupIfConfigured() async {
        guard settings.autoDetectNewPhotos, !running else { return }
        guard await ensurePhotoAccess() else { return }
        currentBackupTask = Task { await runBackup(manual: false) }
    }

    /// Resume upload from where it left off (used when interrupted).
    func resumeUpload() {
        currentBackupTask = Task { await runBackup(manual: true) }
    }

    /// Run a backfill: upload every local asset of the chosen album to the
    /// server now. A manual, explicit action — forces the run even when the
    /// automatic-backup toggle is off, scoped to just that album.
    func runBackfill(albumId: String) {
        showBackfillSheet = false
        var snapshot = settings.snapshot()
        snapshot.selectedAlbumIDs = [albumId]
        currentBackupTask = Task { await runBackup(overrideSettings: snapshot, manual: true) }
    }

    /// Awaits the in-flight backup task, if any (test/coordination helper).
    func awaitCurrentBackup() async {
        await currentBackupTask?.value
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
            .sheet(isPresented: $vm.showBackfillSheet) {
                BackfillSheet(
                    albums: vm.albums,
                    onConfirm: { albumId in
                        vm.runBackfill(albumId: albumId)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        @Bindable var vm = vm
        Section("Auto backup") {
            Toggle("Auto backup", isOn: $vm.settings.isEnabled)
                .onChange(of: vm.settings.isEnabled) { _, newValue in
                    if newValue {
                        // Ask for Photos access (prompt when .notDetermined,
                        // bounce to Settings when denied) AND start the
                        // self-perpetuating background chain — the chain
                        // does not depend on the prompt outcome: while
                        // access is denied the fetches come back empty and
                        // each window is a cheap no-op that re-arms itself.
                        vm.requestPhotoAccessThenOpenDenied()
                        vm.scheduler.submit()
                    }
                }
                .accessibilityIdentifier("autoBackupToggle")
            Toggle("Wi-Fi only", isOn: $vm.settings.onlyOnWiFi)
            Toggle("Charging only", isOn: $vm.settings.onlyWhenCharging)
            Toggle("Exclude screenshots", isOn: $vm.settings.excludeScreenshots)
            Toggle("Exclude camera roll", isOn: $vm.settings.excludeCameraRoll)
            Toggle("Exclude WhatsApp backups", isOn: $vm.settings.excludeWhatsApp)
            Toggle("Auto-detect new photos", isOn: $vm.settings.autoDetectNewPhotos)
            NavigationLink {
                AlbumPickerView(albums: vm.albums, settings: vm.settings)
            } label: {
                LabeledContent("Albums", value: vm.settings.selectedAlbumIDs.isEmpty
                               ? "All"
                               : "\(vm.settings.selectedAlbumIDs.count) selected")
            }
        }
        Section("Backfill") {
            Button {
                vm.showBackfillSheet = true
            } label: {
                Label("Reorganize & Upload", systemImage: "rectangle.on.rectangle.angled")
                    .foregroundStyle(Color.immichPrimary)
            }
            .accessibilityIdentifier("backfillButton")
            if vm.canResume && !vm.running {
                Button {
                    vm.resumeUpload()
                } label: {
                    Label("Resume last backup", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.immichPrimary)
                }
                .accessibilityIdentifier("resumeBackupButton")
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Section("Progress") {
            if vm.running {
                if vm.engine.phase == .checking {
                    ProgressView("Checking library…")
                } else {
                    ProgressView(
                        value: Double(vm.engine.currentIndex),
                        total: max(1, Double(vm.engine.total))
                    )
                }
            }
            if vm.engine.phase != .idle {
                LabeledContent("Uploaded", value: String(vm.engine.uploadedCount))
                LabeledContent("Already on server", value: String(vm.engine.rejectedCount))
                LabeledContent("Failed", value: String(vm.engine.failedCount))
            }
            Button {
                Task { await vm.runBackup(manual: true) }
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

/// Backfill reorganize sheet — pick a local album to bulk-upload to the
/// server. Standard grouped list rows; a single floating Liquid Glass CTA
/// at the bottom triggers the upload. Dismissable via Cancel or swipe.
struct BackfillSheet: View {
    let albums: [BackupAlbum]
    var onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Namespace private var namespace
    @State private var selectedId: String?

    private var selectedCount: Int {
        albums.first(where: { $0.id == selectedId })?.count ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if albums.isEmpty {
                        ContentUnavailableView(
                            "No albums",
                            systemImage: "rectangle.on.rectangle.angled",
                            description: Text("Create an album in Photos first.")
                        )
                    } else {
                        ForEach(albums) { album in
                            Button {
                                selectedId = album.id
                            } label: {
                                HStack(spacing: PVSpacing.s12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .foregroundStyle(Color.immichPrimary)
                                    VStack(alignment: .leading, spacing: PVSpacing.s2) {
                                        Text(album.name)
                                            .foregroundStyle(Color.textPrimaryPV)
                                        Text("\(album.count) photos")
                                            .font(.pvCaption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedId == album.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.immichPrimary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Select an album to upload")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reorganize Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectedId != nil {
                    GlassEffectContainer {
                        Button {
                            if let id = selectedId { onConfirm(id) }
                        } label: {
                            Text("Upload \(selectedCount) photos")
                                .font(.pvHeadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .glassEffect(.regular.tint(Color.immichPrimary), in: Capsule())
                                .glassEffectID("backfill_cta", in: namespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("backfillUploadButton")
                    }
                    .padding(.horizontal, PVSpacing.s16)
                    .padding(.bottom, PVSpacing.s8)
                }
            }
        }
    }
}

/// Floating progress bar shown on the Timeline during active uploads.
struct UploadProgressBanner: View {
    let uploaded: Int
    let total: Int
    let phase: BackupEngine.Phase
    let lastError: String?
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            ProgressView(value: Double(uploaded), total: max(1, Double(total)))
                .progressViewStyle(.circular)
                .tint(Color.immichPrimary)
                .frame(width: 24, height: 24)
                .glassEffect(.regular, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(phrase)
                    .font(.pvSubhead.weight(.semibold))
                Text("\(uploaded) / \(total)")
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            if let error = lastError, phase == .done {
                Button { onRetry() } label: {
                    HStack(spacing: PVSpacing.s4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Retry")
                            .font(.pvSubhead.weight(.semibold))
                    }
                    .foregroundStyle(Color.immichError)
                    .padding(.horizontal, PVSpacing.s8)
                    .padding(.vertical, PVSpacing.s4)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular, in: Rectangle())
        .scrollEdgeEffectStyle(.automatic, for: .top)
    }

    private var phrase: String {
        switch phase {
        case .checking: return "Checking…"
        case .uploading: return "Uploading"
        case .done: return lastError != nil ? "Upload complete" : "Upload complete"
        case .cancelled: return "Cancelled"
        case .idle: return "Uploading"
        }
    }
}
