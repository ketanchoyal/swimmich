import Foundation

/// Resolves a catalog key the way the app does, for tests that assert *which*
/// message a view model surfaces.
///
/// `String(localized:)` follows the language of the running process, so pinning
/// the English source in an expectation makes the test pass or fail with the
/// simulator's language instead of with the code under test. Resolving the
/// expected text through the same catalog keeps the assertion about the code:
/// a wrong key, a wrong count or a missing translation still fails it.
func localizedString(_ key: String) -> String {
    String(localized: String.LocalizationValue(stringLiteral: key))
}

/// Same, with the `%lld` / `%@` placeholders filled in — this reverses the
/// interpolation the call site performed to build the key.
func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localizedString(key), arguments: arguments)
}
