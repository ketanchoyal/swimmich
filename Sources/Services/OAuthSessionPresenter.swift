import Foundation
import AuthenticationServices

/// Presents the Immich OAuth page in an `ASWebAuthenticationSession` and
/// resolves with the callback URL (nil when the user cancels).
///
/// The anchor is the first key-window scene — a fixed scene reference would
/// go stale across scene re-creation.
@MainActor
enum OAuthSessionPresenter {
    /// The scheme the server must redirect back through; must match the
    /// `CFBundleURLTypes` entry in project.yml.
    static let callbackScheme = "app.immich"

    static func present(_ url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, _ in
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = AnchorProvider()
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

/// Minimal presentation-context provider anchored to the first key window.
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first ?? ASPresentationAnchor()
    }
}
