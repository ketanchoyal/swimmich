import Foundation
import Observation

/// Persisted interface language, with the relaunch contract spelled out.
///
/// Two mechanisms are needed and they cover different halves of the app:
///
/// 1. `effectiveLocale` is injected into the view tree's `\.locale`
///    environment by `RootView`, so every `Text("…")` literal re-renders in the
///    new language immediately — the picker, the tab bar, navigation titles.
/// 2. `AppleLanguages` is written so the *next* process launch resolves
///    `Bundle` lookups through the new language. That half is what still
///    matters for strings built outside a view render (`String(localized:)` in
///    view models, notifications, widget copy) — `Locale.current` and the
///    localized bundle are fixed at launch, hence `requiresRelaunch` and the
///    toast that offers to do it.
@MainActor
@Observable
final class AppLanguageStore {
    /// The selected language code, or `nil` for "follow the system".
    static let defaultsKey = "appLanguage"

    private static let appleLanguagesKey = "AppleLanguages"

    private let defaults: UserDefaults

    private(set) var selectedCode: String?

    /// True from the moment the language changes until the next launch actually
    /// applies it everywhere. Drives the relaunch toast.
    private(set) var requiresRelaunch = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedCode = defaults.string(forKey: Self.defaultsKey)
    }

    var useSystemLanguage: Bool { selectedCode == nil }

    var selectedLanguage: AppLanguage? { AppLanguage.language(for: selectedCode) }

    /// Locale for the view tree. `.autoupdatingCurrent` (not `.current`) while
    /// following the system, so the UI follows a device language change without
    /// relaunching the app.
    var effectiveLocale: Locale {
        guard let selectedCode else { return .autoupdatingCurrent }
        return Locale(identifier: selectedCode)
    }

    /// Language the view tree is actually rendering in, system default included.
    /// Comparing on the language (not the full locale identifier) matters:
    /// pinning `en` on an `en_US` device changes nothing on screen, so it must
    /// not raise the "reopen to apply" notice.
    private var resolvedLanguageCode: String? {
        effectiveLocale.language.languageCode?.identifier
    }

    func select(_ language: AppLanguage) {
        apply(code: language.code)
    }

    func applySystemLanguage() {
        apply(code: nil)
    }

    /// Clears the toast once the user has acted on it.
    func markRelaunchHandled() {
        requiresRelaunch = false
    }

    private func apply(code: String?) {
        guard code != selectedCode else { return }
        let previous = resolvedLanguageCode
        selectedCode = code

        if let code {
            defaults.set(code, forKey: Self.defaultsKey)
            // Read by Foundation when the process starts: it decides which
            // `.lproj` `Bundle.main` resolves through. Also the key the system
            // Settings app writes, so an in-app choice keeps winning until the
            // user picks "Use System Language" here.
            defaults.set([code], forKey: Self.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }

        requiresRelaunch = resolvedLanguageCode != previous
    }
}
