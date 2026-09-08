import Foundation

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

    init() {
        self.keychain = KeychainStoreImpl()
        let trustStore = TrustedServerStoreImpl()
        self.trustedServers = trustStore
        self.client = ImmichAPIClient(trustStore: trustStore)
        self.photos = PhotoLibraryServiceImpl()
        self.appLock = AppLockViewModel()
        self.realtime = RealtimeService()
        self.backupScheduler = BGTaskBackupScheduler()
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(client: client as any ImmichClient, keychain: keychain, realtime: realtime)
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

    func makeStorageStatsViewModel() -> StorageStatsViewModel {
        StorageStatsViewModel(client: client as any ImmichClient)
    }
    func makeUploadViewModel() -> UploadViewModel {
        UploadViewModel(client: client as any ImmichClient, photos: photos, scheduler: backupScheduler)
    }

    /// Reads the persisted auto-backup toggle directly — no live VM needed
    /// (the scene-phase code runs outside the tab tree's VMs).
    func isAutoBackupEnabled() -> Bool {
        BackupSettingsStore().isEnabled
    }

    /// Kicks the gated backup engine when auto-backup is configured and
    /// nothing is running (foreground "upload at launch / on return").
    func kickOffAutoBackup() {
        Task {
            let upload = makeUploadViewModel()
            await upload.kickOffAutoBackupIfConfigured()
        }
    }

    func makePeopleViewModel() -> PeopleViewModel {
        PeopleViewModel(client: client as any ImmichClient)
    }

    func makeTagsViewModel() -> TagsViewModel {
        TagsViewModel(client: client as any ImmichClient)
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

    /// AC-615: photo editor VM factory. Editor uses URLSession + ImmichAssetURL directly,
    /// not `ImmichClient`, so we pass nothing but asset identity.
    /// V1.5 polish (AC-718): wire 0.033s render debounce (≈30fps cap) for production.
    func makePhotoEditorViewModel(asset: AssetReactItem) -> PhotoEditorViewModel {
        let vm = PhotoEditorViewModel(assetId: asset.id)
        vm.renderDebounceInterval = 0.033
        return vm
    }
}
