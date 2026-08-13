import Foundation

/// App-wide composition root. Provides pre-built service graph + view models.
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    let client: ImmichAPIClient
    let keychain: KeychainStore
    let photos: PhotoLibraryService
    let appLock: AppLockViewModel

    init() {
        self.keychain = KeychainStoreImpl()
        self.client = ImmichAPIClient()
        self.photos = PhotoLibraryServiceImpl()
        self.appLock = AppLockViewModel()
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(client: client as any ImmichClient, keychain: keychain)
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

    /// AC-615: photo editor VM factory. Editor uses URLSession + ImmichAssetURL directly,
    /// not `ImmichClient`, so we pass nothing but asset identity.
    /// V1.5 polish (AC-718): wire 0.033s render debounce (≈30fps cap) for production.
    func makePhotoEditorViewModel(asset: AssetReactItem) -> PhotoEditorViewModel {
        let vm = PhotoEditorViewModel(assetId: asset.id)
        vm.renderDebounceInterval = 0.033
        return vm
    }
}
