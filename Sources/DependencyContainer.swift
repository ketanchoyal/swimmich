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
}
