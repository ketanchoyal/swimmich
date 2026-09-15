import Foundation
import Observation

/// Thin view model over `WhatsNewStore` (gap G23).
///
/// It keeps **no copy** of "seen / not seen": that fact lives in `UserDefaults`
/// and is re-read from the store on every call, so a view model rebuilt at the
/// next launch — and the one `AuthViewModel` writes past at login — can never
/// disagree about whether the batch has been presented.
@MainActor
@Observable
final class WhatsNewViewModel {
    private let store: WhatsNewStore

    let highlights = FeatureHighlightCatalog.all
    let release = FeatureHighlightCatalog.release

    init(store: WhatsNewStore) {
        self.store = store
    }

    var seenRelease: String { store.seenRelease }

    func shouldPresentAutomatically() -> Bool { store.shouldShow }

    func markSeen() { store.markSeen() }
}
