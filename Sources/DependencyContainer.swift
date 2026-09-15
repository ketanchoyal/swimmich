import Foundation
import ImmichSharedKit

/// App-wide composition root. Provides pre-built service graph + view models.
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    let client: ImmichAPIClient
    let keychain: KeychainStore
    let photos: PhotoLibraryService
    let appLock: AppLockViewModel
    let trustedServers: TrustedServerStore
    let realtime: RealtimeService
    /// Process-wide single instance so the BG handler, the settings toggle
    /// and `UploadViewModel` all submit through the same request slot —
    /// `submit()` cancels then re-submits, so concurrent independent
    /// instances can't step on each other.
    let backupScheduler: any BackgroundBackupScheduling
    /// Process-wide ledger so the BG handler, the foreground kick and the
    /// backup screen all share one loaded copy of the already-backed-up set.
    let backupLedger: any BackupLedgerStoring
    /// Process-wide Live Activity driver: the BG handler, the scene-phase
    /// kick and the backup screen must all drive ONE activity — separate
    /// instances each `Activity.request` their own, pile up concurrent
    /// same-app activities, and the island renders them unreliably (the
    /// "no island while the app is open" symptom).
    let backupLiveActivity: any BackupLiveActivityServicing
    /// Process-wide backup view model — and therefore ONE `BackupEngine`.
    /// Separate instances have separate engines, so their `!running` guards
    /// can't see each other: the scene-phase kick, the BG handler, the
    /// AppIntent and the backup screen would run concurrent passes over the
    /// same library (double iCloud downloads) while fighting over the single
    /// Live Activity — the first one to finish dismisses the island out from
    /// under the other. One VM, one run, one island.
    let upload: UploadViewModel
    /// Watches Photos for inserted assets while the app is in the foreground,
    /// so "Back up new photos automatically" reacts to a photo taken now rather
    /// than only at the next scene activation.
    let libraryMonitor: any PhotoLibraryChangeMonitoring

    /// Offline cache (issue #18). One store per process: the timeline badge,
    /// the viewer and the storage screen must all read the same on-disk index,
    /// and two stores would each hold their own copy of it.
    let offlineStore: OfflineAssetStore
    /// UI mirror of `offlineStore`'s index, injected into the environment so
    /// every grid cell can answer "is this cached?" without a parameter.
    let offlineIndex: OfflineAssetIndex

    /// Process-wide language choice (issue #21). `RootView` injects its locale
    /// into the view tree and every `String(localized:)` call resolves through
    /// `AppleLanguages` at launch, so the store must be the single writer of
    /// both — a second instance would disagree with the one on screen.
    let language: AppLanguageStore

    init() {
        self.keychain = KeychainStoreImpl()
        let trustStore = TrustedServerStoreImpl()
        self.trustedServers = trustStore
        self.client = ImmichAPIClient(trustStore: trustStore)
        self.photos = PhotoLibraryServiceImpl()
        self.appLock = AppLockViewModel()
        self.realtime = RealtimeService()
        self.backupScheduler = BGTaskBackupScheduler()
        self.backupLedger = BackupLedger.persistent()
        self.backupLiveActivity = LiveActivityBackupService()
        self.libraryMonitor = PhotoLibraryChangeMonitor()
        self.offlineStore = OfflineAssetStore()
        self.offlineIndex = OfflineAssetIndex()
        self.language = AppLanguageStore()
        self.upload = UploadViewModel(
            client: client as any ImmichClient, photos: photos,
            ledger: backupLedger, scheduler: backupScheduler,
            activityService: backupLiveActivity
        )
        self.libraryMonitor.onAssetsInserted = { [weak self] in
            self?.kickOffAutoBackup()
        }
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            client: client as any ImmichClient,
            keychain: keychain,
            realtime: realtime,
            // Widgets read the session from the shared keychain group, not from
            // this process (issue #19).
            widgetSession: WidgetSessionStore()
        )
    }

    func makeTimelineViewModel() -> TimelineViewModel {
        TimelineViewModel(client: client as any ImmichClient)
    }

    func makeTrashViewModel() -> TrashViewModel {
        TrashViewModel(client: client as any ImmichClient)
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(client: client as any ImmichClient)
    }

    func makeMapViewModel() -> MapViewModel {
        MapViewModel(client: client as any ImmichClient)
    }

    func makeAlbumsViewModel() -> AlbumsViewModel {
        AlbumsViewModel(client: client as any ImmichClient)
    }

    func makeAlbumDetailViewModel(albumId: String) -> AlbumDetailViewModel {
        AlbumDetailViewModel(client: client as any ImmichClient, albumId: albumId)
    }

    func makeSharedLinksViewModel() -> SharedLinksViewModel {
        SharedLinksViewModel(client: client as any ImmichClient)
    }

    /// Public shared-link viewer (issue #22). Takes the connected server as an
    /// argument: the host check and the public-URL builder both need it, and it
    /// is only known once the app is authenticated.
    func makeSharedLinkViewerViewModel(baseURL: URL, externalDomain: String) -> SharedLinkViewerViewModel {
        SharedLinkViewerViewModel(
            client: client as any ImmichClient,
            baseURL: baseURL,
            externalDomain: externalDomain
        )
    }

    func makeStorageStatsViewModel() -> StorageStatsViewModel {
        StorageStatsViewModel(client: client as any ImmichClient)
    }
    /// Reads the persisted auto-backup toggle directly — no live VM needed
    /// (the scene-phase code runs outside the tab tree's VMs).
    func isAutoBackupEnabled() -> Bool {
        BackupSettingsStore().isEnabled
    }

    /// Kicks the gated backup engine when auto-backup is configured and
    /// nothing is running (foreground "upload at launch / on return").
    func kickOffAutoBackup() {
        Task { await upload.kickOffAutoBackupIfConfigured() }
    }

    /// Aligns the Photos observer with the current settings: observing only
    /// makes sense when both auto-backup and new-photo detection are on, and it
    /// must never be left running otherwise.
    func syncLibraryMonitor() {
        if BackupSettingsStore().snapshot().shouldObserveLibraryChanges {
            libraryMonitor.start()
        } else {
            libraryMonitor.stop()
        }
    }

    func makePeopleViewModel() -> PeopleViewModel {
        PeopleViewModel(client: client as any ImmichClient)
    }

    func makeTagsViewModel() -> TagsViewModel {
        TagsViewModel(client: client as any ImmichClient)
    }

    func makeStacksViewModel() -> StacksViewModel {
        StacksViewModel(client: client as any ImmichClient)
    }

    func makePartnersViewModel() -> PartnersViewModel {
        PartnersViewModel(client: client as any ImmichClient)
    }

    /// Notification permission screen (issue #16). Holds no cache — it reads
    /// the system's answer on appear.
    func makeNotificationsViewModel() -> NotificationsViewModel {
        NotificationsViewModel()
    }

    func makeAdminViewModel() -> AdminViewModel {
        AdminViewModel(client: client as any ImmichClient)
    }

    func makeMemoriesViewModel() -> MemoriesViewModel {
        MemoriesViewModel(client: client as any ImmichClient)
    }

    func makeRoadTripViewModel(
        albumId: String,
        selectedAssetIds: Set<String>?,
        albumTitle: String,
        baseURL: URL,
        token: String?
    ) -> RoadTripViewModel {
        RoadTripViewModel(
            client: client as any ImmichClient,
            albumId: albumId,
            selectedAssetIds: selectedAssetIds,
            albumTitle: albumTitle,
            baseURL: baseURL,
            token: token,
            photos: photos
        )
    }

    func makeDuplicatesViewModel() -> DuplicatesViewModel {
        DuplicatesViewModel(client: client as any ImmichClient)
    }

    /// Offline storage screen (issue #18). Shares the process-wide store and
    /// mirror so a download made in the viewer shows up on the timeline badge
    /// and on this screen without a relaunch.
    func makeOfflineDownloadViewModel() -> OfflineDownloadViewModel {
        OfflineDownloadViewModel(
            store: offlineStore,
            client: client as any ImmichClient,
            index: offlineIndex
        )
    }

    /// Interface-language picker (issue #21). Shares the process-wide store, so
    /// the choice made here is the one `RootView`'s locale and the next launch
    /// read.
    func makeLanguageSettingsViewModel() -> LanguageSettingsViewModel {
        LanguageSettingsViewModel(store: language)
    }

    /// Per-asset upload report (upload-detail). Takes the caller's
    /// `UploadViewModel` rather than choosing one: the screen must project the
    /// engine the process is actually running, and there is only one
    /// (`self.upload`, "One VM, one run, one island").
    func makeUploadDetailViewModel(upload: UploadViewModel) -> UploadDetailViewModel {
        UploadDetailViewModel(upload: upload)
    }

    /// AC-615: photo editor VM factory. Editor uses URLSession + ImmichAssetURL directly,
    /// not `ImmichClient`, so we pass nothing but asset identity.
    /// V1.5 polish (AC-718): wire 0.033s render debounce (≈30fps cap) for production.
    func makePhotoEditorViewModel(asset: AssetReactItem) -> PhotoEditorViewModel {
        let vm = PhotoEditorViewModel(assetId: asset.id)
        vm.renderDebounceInterval = 0.033
        return vm
    }
}
