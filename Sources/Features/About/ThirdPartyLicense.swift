import Foundation

/// A third-party dependency that is **actually embedded** in the app (gap G23).
///
/// Only what ships gets attributed: `project.yml` resolves one SPM package
/// (`SocketIO`), which pulls `Starscream` — nothing else is linked, so nothing
/// else is listed. The text is never copied into Swift; each entry names the
/// attribution file bundled from `Resources/Acknowledgements/`, which is the
/// exact copy shipped by the package and therefore stays correct across
/// dependency updates.
struct ThirdPartyLicense: Identifiable, Hashable {
    let id: String
    let name: String
    /// Base name of the bundled `.txt` attribution file, without extension.
    let resourceName: String

    /// Alphabetical on `name`: the list is read, not searched, and one order
    /// that never changes between launches is the whole requirement.
    static let all: [ThirdPartyLicense] = [
        ThirdPartyLicense(
            id: "socket.io-client-swift",
            name: "Socket.IO-Client-Swift",
            resourceName: "socket.io-client-swift"
        ),
        ThirdPartyLicense(
            id: "starscream",
            name: "Starscream",
            resourceName: "starscream"
        ),
    ]

    /// Thrown when a declared attribution file is not in the bundle — the
    /// packaging failure this feature has to make visible rather than hide.
    enum MissingResourceError: Error {
        case notBundled(String)
    }

    /// The bundled attribution text of `license`.
    ///
    /// `Bundle.main` is the app bundle at the call site and in the unit tests
    /// (they run hosted in the app), so a `Resources/Acknowledgements` entry
    /// forgotten in `project.yml` fails here instead of silently shipping an
    /// empty Licenses screen.
    static func licenseText(for license: ThirdPartyLicense) throws -> String {
        guard let url = Bundle.main.url(forResource: license.resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty
        else {
            throw MissingResourceError.notBundled("\(license.resourceName).txt")
        }
        return text
    }
}
