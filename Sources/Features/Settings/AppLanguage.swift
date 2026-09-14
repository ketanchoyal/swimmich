import Foundation

/// One language the app can be switched to from the Language screen (issue #21).
///
/// The catalog ships `en` as its development language plus `fr`, `de`, `es`
/// and `it`; `supported` is the source of truth for that list, and
/// `available(in:)` narrows it to what the running bundle actually contains —
/// a language whose catalog was never compiled in must not be offered, or
/// picking it would silently show the English source text.
struct AppLanguage: Identifiable, Hashable, Sendable {
    let code: String

    var id: String { code }

    /// Name in the language the app is currently displaying ("French" while the
    /// UI is English, "français" while it is French) — the row's main label.
    var displayName: String {
        Locale.current.localizedString(forIdentifier: code)?.capitalizedFirstLetter ?? code
    }

    /// Name in its own language ("Français"). Always legible to the person
    /// looking for their language, whatever the UI language happens to be.
    var nativeName: String {
        Locale(identifier: code).localizedString(forIdentifier: code)?.capitalizedFirstLetter ?? code
    }

    /// Every language the catalog carries translations for.
    static let supported: [AppLanguage] = [
        AppLanguage(code: "en"),
        AppLanguage(code: "fr"),
        AppLanguage(code: "de"),
        AppLanguage(code: "es"),
        AppLanguage(code: "it")
    ]

    static func language(for code: String?) -> AppLanguage? {
        guard let code else { return nil }
        return supported.first { $0.code == code }
    }

    /// The subset of `supported` present in `bundle`'s localizations.
    ///
    /// The development language (`en`) is always kept: its strings are the
    /// catalog keys themselves, so it has no `.lproj` of its own and would
    /// otherwise fall out of the list.
    static func available(in bundle: Bundle = .main) -> [AppLanguage] {
        let shipped = Set(bundle.localizations)
        return supported.filter { $0.code == "en" || shipped.contains($0.code) }
    }
}

private extension String {
    /// Locale display names come back lowercase in several languages
    /// ("français", "deutsch"); the picker reads better capitalized.
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
