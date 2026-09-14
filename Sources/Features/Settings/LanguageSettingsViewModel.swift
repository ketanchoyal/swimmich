import Foundation
import Observation

/// Interface-language picker (issue #21) — the screen that pins the app's
/// language instead of leaving it to iOS.
///
/// The view model holds no state of its own: `AppLanguageStore` already
/// persists the choice and knows which language this process started in. Every
/// read and every mutation is forwarded to it, so the store stays the single
/// writer and this screen can never disagree with what the next launch reads.
@MainActor
@Observable
final class LanguageSettingsViewModel {
    private let store: AppLanguageStore

    /// The languages the picker offers: the catalog's languages narrowed down to
    /// the ones the running bundle actually carries (a language whose catalog was
    /// never compiled in must not be offered — picking it would silently show the
    /// English source text).
    let languages: [AppLanguage]

    /// Code of the pinned language, or `nil` while the app follows the system.
    var selectedCode: String? { store.selectedCode }

    var useSystemLanguage: Bool { store.useSystemLanguage }

    /// True when the pinned language differs from the one this process launched
    /// in: iOS resolves a bundle's localization once, at launch, so the new
    /// choice only shows up after a restart.
    var requiresRelaunch: Bool { store.requiresRelaunch }

    init(store: AppLanguageStore) {
        self.store = store
        self.languages = AppLanguage.available()
    }

    func isSelected(_ language: AppLanguage) -> Bool {
        store.selectedCode == language.code
    }

    /// Pins `language`. `AppLanguageStore.select` clears the system-following
    /// flag as a side effect, so the toggle turns itself off on its own.
    func select(_ language: AppLanguage) {
        store.select(language)
    }

    /// On: hands the choice back to iOS. Off: pins the language being displayed
    /// right now, so the picker never ends up with no selection at all — and
    /// since that pin matches the running process, no relaunch prompt appears.
    func setUseSystemLanguage(_ enabled: Bool) {
        guard !enabled else {
            store.applySystemLanguage()
            return
        }
        let current = AppLanguage.language(for: store.effectiveLocale.language.languageCode?.identifier)
            ?? languages.first
        if let current {
            store.select(current)
        }
    }

    /// "Got It" on the relaunch notice: the choice stays persisted, the notice
    /// goes away. The next launch reads `AppleLanguages` and resolves every
    /// `String(localized:)` through the new language — iOS ships no supported
    /// API to restart the app itself, so offering a "relaunch" button would be
    /// a dead control.
    func dismissRelaunchPrompt() {
        store.markRelaunchHandled()
    }
}
