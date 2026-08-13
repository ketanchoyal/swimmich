import Foundation
import SwiftUI

/// Authoritative app-wide auth state. Drives RootView routing.
///
/// FM-4: implements AuthSessionDelegate so any 401 anywhere resets state.
///
/// Session persistence: the bearer token lives in the Keychain; the server URL
/// + user identity live in UserDefaults. `restoreSession()` reconfigures the
/// shared `ImmichClient` on launch (it is otherwise only configured during
/// login/server discovery), so the app stays authenticated across relaunches.
@MainActor
@Observable
final class AuthViewModel: AuthSessionDelegate {
    enum ServerStatus: Equatable {
        case idle
        case checking
        case reachable(version: ServerVersionResponseDto?)
        case unreachable
    }

    // UserDefaults keys (internal so tests can seed/assert).
    static let serverURLDefaultsKey = "authServerURL"
    static let userEmailDefaultsKey = "authUserEmail"
    static let userNameDefaultsKey = "authUserName"
    static let userIdDefaultsKey = "authUserId"
    static let isAdminDefaultsKey = "authIsAdmin"

    /// OAuth callback scheme — must match the `CFBundleURLTypes` entry.
    static let oauthRedirectURI = "app.immich://oauth-callback"

    /// Injectable browser-session hook. Production default runs an
    /// `ASWebAuthenticationSession`; tests inject a mock closure.
    var oauthSessionHandler: (URL) async -> URL? = { url in
        await OAuthSessionPresenter.present(url)
    }

    // Server connection
    var serverURLString: String = "" {
        didSet { _cachedBaseURL = nil }
    }
    var serverStatus: ServerStatus = .idle
    var serverConfig: ServerConfigDto?

    // Session
    var accessToken: String?
    var userEmail: String?
    var userName: String?
    var userId: String?
    var isAdmin: Bool = false
    var isAuthenticated: Bool { accessToken != nil }

    /// True while `restoreSession()` reconfigures the client + validates the
    /// stored token. RootView gates on this to avoid a TabView→onboarding
    /// flash before validation settles.
    var isRestoringSession: Bool = false

    // UI
    var isLoading: Bool = false
    var errorMessage: String?

    private let client: any ImmichClient
    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private let trustStore: TrustedServerStore
    private var _cachedBaseURL: URL?

    init(
        client: any ImmichClient,
        keychain: KeychainStore,
        defaults: UserDefaults = .standard,
        trustStore: TrustedServerStore = TrustedServerStoreImpl()
    ) {
        self.client = client
        self.keychain = keychain
        self.defaults = defaults
        self.trustStore = trustStore
        self.serverURLString = defaults.string(forKey: Self.serverURLDefaultsKey) ?? ""
        self.userEmail = defaults.string(forKey: Self.userEmailDefaultsKey)
        self.userName = defaults.string(forKey: Self.userNameDefaultsKey)
        self.userId = defaults.string(forKey: Self.userIdDefaultsKey)
        self.isAdmin = defaults.bool(forKey: Self.isAdminDefaultsKey)
        self.accessToken = keychain.getToken()
        self.client.authDelegate = self
    }

    // MARK: - Session restore (relaunch)

    /// Reconfigures the shared client from the stored session and validates
    /// the token. Called by RootView via `.task` on launch.
    ///
    /// - Valid token → stays authenticated (no-op beyond configuring the client).
    /// - `.unauthorized` → `resetSession()` (clean sign-in again, URL pre-filled).
    /// - Network failure → keeps the session (offline-safe; a real 401 later
    ///   still resets via FM-4).
    func restoreSession() async {
        guard !isRestoringSession else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        guard let token = accessToken, let url = baseURL else {
            resetSession()
            return
        }
        client.configure(baseURL: url, token: token)
        do {
            _ = try await client.validateToken()
        } catch APIError.unauthorized {
            resetSession()
        } catch {
            // Network / decode: keep the session; don't wipe on transient offline.
        }
    }

    // MARK: - URL helpers

    /// Normalizes a raw user-entered URL string into a base URL.
    /// Trims trailing slash, defaults scheme to https.
    func normalizedBaseURL(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return URL(string: trimmed)
    }

    var baseURL: URL? {
        if let cached = _cachedBaseURL { return cached }
        let url = normalizedBaseURL(from: serverURLString)
        _cachedBaseURL = url
        return url
    }

    // MARK: - Server discovery

    @MainActor
    func connectServer() async {
        guard let url = baseURL else {
            serverStatus = .unreachable
            errorMessage = "Enter a valid server URL."
            return
        }
        serverStatus = .checking
        errorMessage = nil
        pendingUntrustedHost = nil
        client.configure(baseURL: url, token: keychain.getToken())
        do {
            let ping = try await client.ping()
            if ping.res == "pong" {
                let version = try? await client.serverVersion()
                serverStatus = .reachable(version: version)
                serverConfig = try? await client.serverConfig()
                defaults.set(url.absoluteString, forKey: Self.serverURLDefaultsKey)
            } else {
                serverStatus = .unreachable
            }
        } catch let e as URLError where Self.isTLSError(e) {
            // P5 selfsigned-cert: surface the host so the UI can offer to
            // trust it explicitly.
            serverStatus = .unreachable
            errorMessage = "Le certificat de ce serveur ne peut pas être vérifié."
            pendingUntrustedHost = url.host
        } catch {
            serverStatus = .unreachable
        }
    }

    /// Host whose TLS certificate failed validation (P5 selfsigned-cert).
    var pendingUntrustedHost: String?

    /// Persists the pending host as trusted and re-runs connectivity.
    @MainActor
    func trustPendingServer() async {
        guard let host = pendingUntrustedHost else { return }
        trustStore.add(host)
        pendingUntrustedHost = nil
        await connectServer()
    }

    /// TLS certificate failures that warrant the explicit trust flow.
    static func isTLSError(_ error: URLError) -> Bool {
        switch error.code {
        case .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid:
            return true
        default:
            return false
        }
    }

    // MARK: - Auth

    @MainActor
    func login(email: String, password: String) async {
        guard baseURL != nil else {
            errorMessage = "Connect to a server first."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.login(email: email, password: password)
            applySession(
                token: response.accessToken,
                email: response.userEmail,
                name: response.name,
                userId: response.userId,
                isAdmin: response.isAdmin
            )
        } catch let e {
            errorMessage = e.localizedDescription
        }
        isLoading = false
    }

    // MARK: - OAuth (P5)

    /// True when the server exposes OAuth (non-empty `oauthButtonText`).
    var canOAuthLogin: Bool {
        guard let text = serverConfig?.oauthButtonText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Mobile OAuth flow (P5): GET the provider URL → browser session →
    /// exchange the callback code → apply the session like a normal login.
    /// Cancelling the browser leaves the current state untouched.
    @MainActor
    func startOAuthFlow() async {
        guard let url = baseURL, canOAuthLogin else {
            errorMessage = "OAuth is not enabled on this server."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let mobile = try await client.getOAuthMobileURL(redirectURI: Self.oauthRedirectURI)
            guard let providerURL = URL(string: mobile.url) else {
                errorMessage = "The server returned an invalid OAuth URL."
                return
            }
            guard let callbackURL = await oauthSessionHandler(providerURL) else {
                return // User cancelled — keep the current state.
            }
            let response = try await client.exchangeOAuthCode(
                url: callbackURL.absoluteString,
                redirectURI: Self.oauthRedirectURI
            )
            applySession(
                token: response.accessToken,
                email: response.email,
                name: response.name,
                userId: nil,
                isAdmin: response.isAdmin
            )
        } catch let e {
            errorMessage = e.localizedDescription
        }
        isLoading = false
    }

    /// Applies a successful auth response: state + Keychain + UserDefaults +
    /// client reconfiguration. Shared by password login and OAuth.
    private func applySession(token: String, email: String?, name: String?, userId: String?, isAdmin: Bool) {
        accessToken = token
        userEmail = email
        userName = name
        self.userId = userId
        self.isAdmin = isAdmin
        keychain.saveToken(token)
        defaults.set(baseURL?.absoluteString ?? serverURLString, forKey: Self.serverURLDefaultsKey)
        if let email { defaults.set(email, forKey: Self.userEmailDefaultsKey) }
        if let name { defaults.set(name, forKey: Self.userNameDefaultsKey) }
        if let userId { defaults.set(userId, forKey: Self.userIdDefaultsKey) }
        defaults.set(isAdmin, forKey: Self.isAdminDefaultsKey)
        client.configure(baseURL: baseURL, token: token)
    }

    @MainActor
    func logout() async {
        isLoading = true
        _ = try? await client.logout()
        resetSession()
        isLoading = false
    }

    /// Clears auth state + stored credentials. Keeps the server URL so the
    /// next sign-in skips re-entering the address.
    func resetSession() {
        accessToken = nil
        userEmail = nil
        userName = nil
        userId = nil
        isAdmin = false
        keychain.deleteToken()
        defaults.removeObject(forKey: Self.userEmailDefaultsKey)
        defaults.removeObject(forKey: Self.userNameDefaultsKey)
        defaults.removeObject(forKey: Self.userIdDefaultsKey)
        defaults.removeObject(forKey: Self.isAdminDefaultsKey)
        client.configure(baseURL: baseURL, token: nil)
    }

    // MARK: - AuthSessionDelegate (FM-4)

    func didReceiveUnauthorized() {
        Task { @MainActor in
            resetSession()
        }
    }
}
