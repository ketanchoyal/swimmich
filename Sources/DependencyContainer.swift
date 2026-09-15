import Foundation
import ImmichSharedKit

/// App-wide composition root. Provides pre-built service graph + view models.
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    let client: ImmichAPIClient
    let keychain: KeychainStore
    let photos: PhotoLibraryService
    /// The destructive half of the Photos surface (gap G1). Same object as
    /// `photos` — see `photoLibrary`.
    let cleanupSource: any LocalCleanupSource
    /// The one PhotosKit service behind `photos` and `cleanupSource`. Stored
    /// concretely because the album list Free Up Space offers is only reachable
    /// through `BackupAssetSource`: a second `PhotoLibraryServiceImpl` would
    /// rebuild its own iCloud-shared-album set, and the screen that offers a
    /// deletion would disagree with the one performing it.
    private let photoLibrary: PhotoLibraryServiceImpl
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

    /// Persisted device album → server album map, one per process for the same
    /// reason as `upload`: a second store could disagree about which album a
    /// mirrored album already has.
    let albumSyncStore: AlbumSyncStore
    /// The one album mirror this process owns. Two services would each hold
    /// their own buffer, and the second would lose half a run's assets.
    let albumSyncService: AlbumSyncService

    /// Offline cache (issue #18). One store per process: the timeline badge,
    /// the viewer and the storage screen must all read the same on-disk index,
    /// and two stores would each hold their own copy of it.
    let offlineStore: OfflineAssetStore
    /// UI mirror of `offlineStore`'s index, injected into the environment so
    /// every grid cell can answer "is this cached?" without a parameter.
    let offlineIndex: OfflineAssetIndex

    /// Process-wide external-screen state (gap G9). One instance for the whole
    /// app for the same reason as `upload`: the route detector and its
    /// notifications are system resources, the viewer can be opened from eight
    /// surfaces, and a per-viewer service would leave the badge wrong the first
    /// time the viewer opens.
    let castService: any CastService = AirPlayCastService()

    /// Backup-state mirror (G6), same shape and same reason as `offlineIndex`:
    /// one instance per process, rebuilt from the ledger on every ledger write
    /// and read by every thumbnail cell through the environment.
    let cloudStatus: CloudBackupStatusIndex

    /// Process-wide language choice (issue #21). `RootView` injects its locale
    /// into the view tree and every `String(localized:)` call resolves through
    /// `AppleLanguages` at launch, so the store must be the single writer of
    /// both — a second instance would disagree with the one on screen.
    let language: AppLanguageStore

    /// Process-wide map settings (gap G14b). Same shape of reasoning as
    /// `language`: the map, its settings sheet, its filter badge and the photo
    /// sheet's banner must all project ONE filter, and the choice has to
    /// outlive the segment view that presents the sheet.
    let mapSettings: MapSettingsStore

    /// Process-wide download queue (gap G10). Same reasoning as `upload`: the
    /// floating panel, the viewer's "Download to Files" and the timeline's
    /// mass action must all drive ONE queue — and it has to outlive the screen
    /// that started the download, where a queue built per presentation dies
    /// with the sheet (exactly the defect this feature fixes).
    let downloadQueue: DownloadQueueViewModel

    /// Keychain slot for the locked folder's remembered PIN (gap G12). One
    /// store per process so the folder's ViewModel and any future Face ID
    /// shortcut read the same entry; never the session token slot.
    let lockedFolderPINs: any LockedFolderPINStoring

    init() {
        self.keychain = KeychainStoreImpl()
        let trustStore = TrustedServerStoreImpl()
        self.trustedServers = trustStore
        self.client = ImmichAPIClient(trustStore: trustStore)
        // One PhotosKit service for the whole app: the album list, the export
        // path and the deletion path all have to describe the same library.
        let photoLibrary = PhotoLibraryServiceImpl()
        self.photoLibrary = photoLibrary
        self.photos = photoLibrary
        self.cleanupSource = photoLibrary
        self.appLock = AppLockViewModel()
        self.lockedFolderPINs = KeychainLockedFolderPINStore(keychain: keychain)
        self.realtime = RealtimeService()
        self.backupScheduler = BGTaskBackupScheduler()
        self.backupLedger = BackupLedger.persistent()
        self.backupLiveActivity = LiveActivityBackupService()
        self.libraryMonitor = PhotoLibraryChangeMonitor()
        self.offlineStore = OfflineAssetStore()
        self.offlineIndex = OfflineAssetIndex()
        self.language = AppLanguageStore()
        self.mapSettings = MapSettingsStore()
        let cloudStatus = CloudBackupStatusIndex()
        self.cloudStatus = cloudStatus
        self.albumSyncStore = AlbumSyncStore()
        self.albumSyncService = AlbumSyncService(
            mapping: albumSyncStore,
            // Same chunk size as the dedup check and the ledger reconciliation:
            // the mirror receives it instead of hard-coding a second copy.
            batchSize: BackupEngine.checkChunkSize
        )
        self.upload = UploadViewModel(
            client: client as any ImmichClient, photos: photos,
            ledger: backupLedger, scheduler: backupScheduler,
            activityService: backupLiveActivity,
            cloudStatus: cloudStatus,
            albumSync: albumSyncService,
            // Read per run, not captured: a login that happens after this
            // composition root was built must still mirror, and the mapping is
            // keyed by the account that owns the albums.
            userID: { UserDefaults.standard.string(forKey: AuthViewModel.userIdDefaultsKey) }
        )
        // Seed the badge index before anything can draw a tile, then re-read it
        // on every ledger write — the engine's runs are the only thing that adds
        // or removes a "proven on the server" fact.
        let ledger = backupLedger
        cloudStatus.refresh(ledger: ledger)
        upload.engine.onLedgerChange = { cloudStatus.refresh(ledger: ledger) }
        upload.syncBadgeIndex()
        // Foreground-only by construction: `URLSessionFileDownloadTransport`
        // takes `.shared`, so a transfer pauses when iOS suspends the app. A
        // background `URLSession` would need its own identifier, an app-delegate
        // hand-off and a reconciliation pass at launch — none of which this
        // card asks for; the panel is what keeps the run visible, not a
        // background session. The transport is the same type the offline cache
        // uses, so nothing new goes on the wire.
        self.downloadQueue = DownloadQueueViewModel(client: client as any ImmichClient, transport: URLSessionFileDownloadTransport())
        self.libraryMonitor.onAssetsInserted = { [weak self] in
            self?.kickOffAutoBackup()
        }
        // Gap G9: the route is watched for the whole process, with the
        // container's interest as the permanent one — a cast sheet opening and
        // closing only adds and releases its own.
        castService.startObserving()
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

    /// One view model per "recent" sort axis (gap G13). Two instances, not one:
    /// the two screens keep their own bucket list and their own scroll, so
    /// nothing but the mode parameter is shared.
    func makeRecentAssetsViewModel(mode: RecentAssetsMode) -> RecentAssetsViewModel {
        RecentAssetsViewModel(client: client as any ImmichClient, mode: mode)
    }

    func makeTrashViewModel() -> TrashViewModel {
        TrashViewModel(client: client as any ImmichClient)
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(client: client as any ImmichClient)
    }

    func makeMapViewModel() -> MapViewModel {
        MapViewModel(client: client as any ImmichClient, settings: mapSettings)
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

    /// The album mirror, for callers that need it explicitly. Always the single
    /// process-wide instance — same reasoning as `container.upload`: a second
    /// service would hold a second buffer, and half a run's assets would wait in
    /// a buffer nobody flushes.
    func makeAlbumSyncService() -> AlbumSyncService { albumSyncService }

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

    /// Folder view (gap G11). Read-only and stateless outside the VM: the tree
    /// and the per-folder asset cache live in the instance and nothing is
    /// persisted, so there is no store to share here — one VM per screen tree.
    func makeFolderViewModel() -> FolderViewModel {
        FolderViewModel(client: client as any ImmichClient)
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

    /// The one download queue of the process — the same instance the floating
    /// panel projects, the viewer enqueues into and the timeline's mass action
    /// hands its selection to. Never a fresh instance: a second queue would
    /// show its own rows and cancel tasks the panel is following.
    func makeDownloadQueueViewModel() -> DownloadQueueViewModel { downloadQueue }
    /// Cast sheet of the viewer (gap G9). Projection only — the ViewModel stores
    /// no state, so a fresh instance per presentation is free and always current
    /// with the process-wide `castService` it projects.
    func makeCastViewModel() -> CastViewModel {
        CastViewModel(service: castService)
    }

    /// Sync status screen (AC-5030–5039). Takes both view models explicitly:
    /// the container must not pick which engine of the process is observed, and
    /// `RootView` already holds the process-wide `upload`.
    func makeSyncStatusViewModel(
        upload: UploadViewModel,
        offline: OfflineDownloadViewModel
    ) -> SyncStatusViewModel {
        SyncStatusViewModel(upload: upload, offline: offline)
    }

    /// Interface-language picker (issue #21). Shares the process-wide store, so
    /// the choice made here is the one `RootView`'s locale and the next launch
    /// read.
    func makeLanguageSettingsViewModel() -> LanguageSettingsViewModel {
        LanguageSettingsViewModel(store: language)
    }

    func makeDeviceSessionsViewModel() -> DeviceSessionsViewModel {
        DeviceSessionsViewModel(client: client as any ImmichClient)
    }

    /// Profile picture screen (gap G16). Takes the session as an argument for
    /// the same reason as `makeSharedLinkViewerViewModel`: the container knows
    /// the client, but the connected server and its bearer token only exist
    /// once the app is authenticated.
    func makeProfilePictureViewModel(baseURL: URL?, token: String?) -> ProfilePictureViewModel {
        ProfilePictureViewModel(client: client as any ImmichClient, baseURL: baseURL, token: token)
    }

    /// Per-asset upload report (upload-detail). Takes the caller's
    /// `UploadViewModel` rather than choosing one: the screen must project the
    /// engine the process is actually running, and there is only one
    /// (`self.upload`, "One VM, one run, one island").
    func makeUploadDetailViewModel(upload: UploadViewModel) -> UploadDetailViewModel {
        UploadDetailViewModel(upload: upload)
    }

    /// "On this device" (local library). Reads the same Photos instance the
    /// backup engine reads (`PhotoLibraryServiceImpl` is both the library
    /// service and the backup asset source) and the same client for the remote
    /// aggregate, so the screen and a backup run can never disagree about what
    /// the device holds.
    func makeLocalLibraryViewModel() -> LocalLibraryViewModel {
        LocalLibraryViewModel(
            photoLibrary: photos,
            albumSource: (photos as? BackupAssetSource) ?? PhotoLibraryServiceImpl(),
            client: client as any ImmichClient
        )
    }

    /// Free Up Space (gap G1). The ledger passed here is the SAME instance the
    /// backup engine writes: it is the only record of which checksums the server
    /// was told about, and a fresh ledger would make the scan find nothing.
    func makeFreeUpSpaceViewModel() -> FreeUpSpaceViewModel {
        FreeUpSpaceViewModel(
            client: client as any ImmichClient,
            source: cleanupSource,
            albumSource: photoLibrary,
            ledger: backupLedger,
            settings: CleanupSettingsStore()
        )
    }

    /// AC-615: photo editor VM factory. Editor uses URLSession + ImmichAssetURL directly,
    /// not `ImmichClient`, so we pass nothing but asset identity.
    /// V1.5 polish (AC-718): wire 0.033s render debounce (≈30fps cap) for production.
    func makePhotoEditorViewModel(asset: AssetReactItem) -> PhotoEditorViewModel {
        let vm = PhotoEditorViewModel(assetId: asset.id)
        vm.renderDebounceInterval = 0.033
        return vm
    }

    /// Locked folder (gap G12). Takes the active account because the remembered
    /// PIN is stored per account — two servers must never share one code.
    func makeLockedFolderViewModel(accountID: String) -> LockedFolderViewModel {
        LockedFolderViewModel(
            client: client as any ImmichClient,
            pins: lockedFolderPINs,
            accountID: accountID
        )
    }
}
