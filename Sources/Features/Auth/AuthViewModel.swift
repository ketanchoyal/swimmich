import Foundation
import SwiftUI

/// Authoritative app-wide auth state. Drives RootView routing.
///
/// FM-4: implements AuthSessionDelegate so any 401 anywhere resets state.
@MainActor
@Observable
final class AuthViewModel: AuthSessionDelegate {
    enum ServerStatus: Equatable {
        case idle
        case checking
        case reachable(version: ServerVersionResponseDto?)
        case unreachable
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
    var isAuthenticated: Bool { accessToken != nil }

    // UI
    var isLoading: Bool = false
    var errorMessage: String?

    private let client: any ImmichClient
    private let keychain: KeychainStore
    private var _cachedBaseURL: URL?

    init(client: any ImmichClient, keychain: KeychainStore) {
        self.client = client
        self.keychain = keychain
        self.accessToken = keychain.getToken()
        self.client.authDelegate = self
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
        client.configure(baseURL: url, token: keychain.getToken())
        do {
            let ping = try await client.ping()
            if ping.res == "pong" {
                let version = try? await client.serverVersion()
                serverStatus = .reachable(version: version)
                serverConfig = try? await client.serverConfig()
            } else {
                serverStatus = .unreachable
            }
        } catch {
            serverStatus = .unreachable
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
            accessToken = response.accessToken
            userEmail = response.userEmail
            userName = response.name
            userId = response.userId
            keychain.saveToken(response.accessToken)
            client.configure(baseURL: baseURL, token: response.accessToken)
        } catch let e {
            errorMessage = e.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func logout() async {
        isLoading = true
        _ = try? await client.logout()
        resetSession()
        isLoading = false
    }

    func resetSession() {
        accessToken = nil
        userEmail = nil
        userName = nil
        userId = nil
        keychain.deleteToken()
        client.configure(baseURL: baseURL, token: nil)
    }

    // MARK: - AuthSessionDelegate (FM-4)

    func didReceiveUnauthorized() {
        Task { @MainActor in
            resetSession()
        }
    }
}
