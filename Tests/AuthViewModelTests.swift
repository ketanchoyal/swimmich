import XCTest
@testable import ImmichSwiftUI

final class AuthViewModelTests: XCTestCase {

    // AC-003: login sends {email,password} to POST /api/auth/login.
    @MainActor
    func test_AC_003_loginSendsCorrectBody() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.login(email: "test@example.com", password: "secret123")

        XCTAssertEqual(mock.lastLoginBody?.email, "test@example.com")
        XCTAssertEqual(mock.lastLoginBody?.password, "secret123")
        XCTAssertGreaterThan(mock.requestCount, 0)
    }

    // AC-004: on login success, JWT is persisted to Keychain.
    @MainActor
    func test_AC_004_loginPersistsTokenToKeychain() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "fake-jwt", userId: "u", userEmail: "t@e.com", name: "T",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.login(email: "t@e.com", password: "secret")
        XCTAssertEqual(keychain.savedToken, "fake-jwt")
        XCTAssertTrue(auth.isAuthenticated)
    }

    // AC-005: logout clears Keychain + isAuthenticated = false.
    @MainActor
    func test_AC_005_logoutClearsKeychainAndIsAuthenticated() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "pre-jwt", userId: "u", userEmail: "t@e.com", name: "T",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.login(email: "t@e.com", password: "secret")
        XCTAssertEqual(keychain.savedToken, "pre-jwt")

        await auth.logout()
        XCTAssertNil(keychain.savedToken)
        XCTAssertFalse(auth.isAuthenticated)
    }

    // AC-012: unreachable server → status = .unreachable, isAuthenticated = false.
    @MainActor
    func test_AC_012_connectServerUnreachable() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.pingError = URLError(.cannotConnectToHost)

        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.connectServer()
        XCTAssertEqual(auth.serverStatus, .unreachable)
        XCTAssertFalse(auth.isAuthenticated)
    }

    // AC-012b: ping response decoded as ServerPingResponse JSON {"res":"pong"} → reachable.
    @MainActor
    func test_AC_012b_pingDecodedAndReachable() async throws {
        let json = #"{"res":"pong"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(ServerPingResponse.self, from: json)
        XCTAssertEqual(decoded.res, "pong")

        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.pingResponse = ServerPingResponse(res: "pong")
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.connectServer()
        if case .reachable = auth.serverStatus {
            // ok
        } else {
            XCTFail("expected .reachable, got \(auth.serverStatus)")
        }
    }

    // MARK: - Session restore (auth persistence across relaunch)

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suite = "AuthViewModelTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    /// Seed a stored session: server URL in defaults + token in keychain.
    private func makeStoredSession(defaults: UserDefaults, keychain: MockKeychainStore, url: String = "https://photos.example.com", token: String = "saved-jwt") {
        defaults.set(url, forKey: AuthViewModel.serverURLDefaultsKey)
        keychain.saveToken(token)
    }

    // AC-720: valid stored session → client reconfigured + stays authenticated.
    @MainActor
    func test_restoreSession_restoresSessionAndConfiguresClient() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        makeStoredSession(defaults: defaults, keychain: keychain)
        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)

        XCTAssertTrue(auth.isAuthenticated, "token restored from keychain")
        XCTAssertEqual(auth.serverURLString, "https://photos.example.com")

        await auth.restoreSession()

        XCTAssertEqual(mock.configuredToken, "saved-jwt", "client must be reconfigured at startup")
        XCTAssertEqual(mock.configuredBaseURL?.absoluteString, "https://photos.example.com")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isRestoringSession)
        XCTAssertEqual(mock.requestCount, 1, "validateToken called once")
    }

    // AC-720: invalid token → session reset + keychain cleared (clean re-login).
    @MainActor
    func test_restoreSession_invalidToken_resetsSession() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        makeStoredSession(defaults: defaults, keychain: keychain)
        let mock = MockImmichClient()
        mock.validateError = APIError.unauthorized
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)

        await auth.restoreSession()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(keychain.savedToken, "rejected token must be deleted")
        XCTAssertNil(auth.userEmail)
        XCTAssertEqual(defaults.string(forKey: AuthViewModel.serverURLDefaultsKey), "https://photos.example.com", "server URL survives for next sign-in")
    }

    // AC-720: offline at launch → session kept (never wipe on transient network error).
    @MainActor
    func test_restoreSession_networkError_keepsSession() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        makeStoredSession(defaults: defaults, keychain: keychain)
        let mock = MockImmichClient()
        mock.validateError = URLError(.notConnectedToInternet)
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)

        await auth.restoreSession()

        XCTAssertTrue(auth.isAuthenticated, "offline launch must not wipe the session")
        XCTAssertEqual(keychain.savedToken, "saved-jwt")
    }

    // AC-720: nothing stored → clean reset (no crash, onboarding shows).
    @MainActor
    func test_restoreSession_noStoredSession_resets() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)

        await auth.restoreSession()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isRestoringSession)
        XCTAssertEqual(mock.requestCount, 0, "no validation without a session")
    }

    // AC-721: login persists server URL + user identity for next relaunch.
    @MainActor
    func test_login_persistsServerURLAndIdentity() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "jwt", userId: "u1", userEmail: "alice@example.com", name: "Alice",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "photos.example.com"
        _ = auth.baseURL

        await auth.login(email: "alice@example.com", password: "secret")

        XCTAssertEqual(defaults.string(forKey: AuthViewModel.serverURLDefaultsKey), "https://photos.example.com")
        XCTAssertEqual(defaults.string(forKey: AuthViewModel.userEmailDefaultsKey), "alice@example.com")
        XCTAssertEqual(defaults.string(forKey: AuthViewModel.userNameDefaultsKey), "Alice")
        XCTAssertEqual(defaults.string(forKey: AuthViewModel.userIdDefaultsKey), "u1")
    }

    // Album share: isAdmin is persisted at login and restored on relaunch —
    // the "Shared With" sheet needs it to pick the right empty-state message.
    @MainActor
    func test_login_persistsAndRestoresIsAdmin() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "jwt", userId: "u1", userEmail: "admin@example.com", name: "Admin",
            profileImagePath: "", isAdmin: true, shouldChangePassword: false, isOnboarded: true
        )
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "photos.example.com"
        _ = auth.baseURL

        await auth.login(email: "admin@example.com", password: "secret")
        XCTAssertTrue(auth.isAdmin)
        XCTAssertTrue(defaults.bool(forKey: AuthViewModel.isAdminDefaultsKey))

        // Simulated relaunch: a fresh VM reads the stored flag.
        let restored = AuthViewModel(client: MockImmichClient(), keychain: MockKeychainStore(), defaults: defaults)
        XCTAssertTrue(restored.isAdmin, "isAdmin must survive relaunch")
    }

    // MARK: - Self-signed cert trust (P5)

    @MainActor
    func test_connectServer_tlsErrorSetsPendingUntrustedHost() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.pingError = URLError(.serverCertificateUntrusted)
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        await auth.connectServer()

        XCTAssertEqual(auth.serverStatus, .unreachable)
        XCTAssertEqual(auth.pendingUntrustedHost, "photos.example.com")
    }

    @MainActor
    func test_connectServer_networkErrorDoesNotSetTrustHost() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.pingError = URLError(.timedOut)
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        await auth.connectServer()

        XCTAssertEqual(auth.serverStatus, .unreachable)
        XCTAssertNil(auth.pendingUntrustedHost)
    }

    @MainActor
    func test_trustPendingServer_addsHostAndReconnects() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let trustSuite = "trustVM-\(UUID().uuidString)"
        let trustDefaults = UserDefaults(suiteName: trustSuite)!
        defer { trustDefaults.removePersistentDomain(forName: trustSuite) }
        let trustStore = TrustedServerStoreImpl(defaults: trustDefaults)

        let mock = MockImmichClient()
        // First ping fails TLS, second succeeds (after trust).
        mock.pingResSequences = [.init(res: "pong")]
        mock.pingError = URLError(.serverCertificateUntrusted)
        let auth = AuthViewModel(
            client: mock, keychain: MockKeychainStore(), defaults: defaults, trustStore: trustStore
        )
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        await auth.connectServer()
        XCTAssertEqual(auth.pendingUntrustedHost, "photos.example.com")

        // After trust: no TLS error anymore.
        mock.pingError = nil
        await auth.trustPendingServer()

        XCTAssertTrue(trustStore.contains("photos.example.com"))
        XCTAssertNil(auth.pendingUntrustedHost)
        guard case .reachable = auth.serverStatus else {
            return XCTFail("Expected reachable, got \(auth.serverStatus)")
        }
    }

    // MARK: - OAuth (P5)

    private func makeOAuthConfig() -> ServerConfigDto {
        ServerConfigDto(
            oauthButtonText: "Continue with Immich SSO", loginPageMessage: "", trashDays: 30,
            userDeleteDelay: 7, isInitialized: true, isOnboarded: true, externalDomain: "",
            publicUsers: false, mapDarkStyleUrl: "", mapLightStyleUrl: "",
            maintenanceMode: false, minFaces: 0
        )
    }

    private func makeOAuthConfigEmptyText() -> ServerConfigDto {
        ServerConfigDto(
            oauthButtonText: "", loginPageMessage: "", trashDays: 30,
            userDeleteDelay: 7, isInitialized: true, isOnboarded: true, externalDomain: "",
            publicUsers: false, mapDarkStyleUrl: "", mapLightStyleUrl: "",
            maintenanceMode: false, minFaces: 0
        )
    }

    @MainActor
    func test_oauth_canOAuthLogin_requiresButtonText() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(client: MockImmichClient(), keychain: MockKeychainStore(), defaults: defaults)
        auth.serverConfig = makeOAuthConfig()

        XCTAssertTrue(auth.canOAuthLogin)
        auth.serverConfig = makeOAuthConfigEmptyText()
        XCTAssertFalse(auth.canOAuthLogin)
        auth.serverConfig = nil
        XCTAssertFalse(auth.canOAuthLogin)
    }

    @MainActor
    func test_oauth_flowExchangesCodeAndAppliesSession() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.oauthCallbackResponse = OAuthCallbackResponseDto(
            accessToken: "oauth-jwt", isAdmin: true, name: "OAuth Alice",
            email: "alice@sso.example.com", profileImagePath: "", shouldChangePassword: false
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL
        auth.serverConfig = makeOAuthConfig()
        auth.oauthSessionHandler = { url in
            XCTAssertEqual(url.absoluteString, "https://sso.example.com/authorize")
            return URL(string: "app.immich://oauth-callback?code=abc")
        }

        await auth.startOAuthFlow()

        XCTAssertEqual(mock.lastOAuthRedirectURI, AuthViewModel.oauthRedirectURI)
        XCTAssertEqual(mock.lastOAuthCallbackURL, "app.immich://oauth-callback?code=abc")
        XCTAssertEqual(mock.lastOAuthCallbackRedirectURI, AuthViewModel.oauthRedirectURI)
        XCTAssertEqual(keychain.savedToken, "oauth-jwt")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isAdmin)
        XCTAssertEqual(auth.userName, "OAuth Alice")
    }

    @MainActor
    func test_oauth_cancelLeavesStateUntouched() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL
        auth.serverConfig = makeOAuthConfig()
        auth.oauthSessionHandler = { _ in nil }

        await auth.startOAuthFlow()

        XCTAssertNil(auth.accessToken)
        XCTAssertNil(keychain.savedToken)
        XCTAssertNil(auth.errorMessage)
        XCTAssertEqual(mock.requestCount, 1, "Only the mobile-URL call; no callback exchange")
    }

    @MainActor
    func test_oauth_failureSetsError() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.oauthError = APIError.serverError(500, "boom")
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL
        auth.serverConfig = makeOAuthConfig()
        auth.oauthSessionHandler = { _ in URL(string: "app.immich://oauth-callback?code=abc") }

        await auth.startOAuthFlow()

        XCTAssertNil(auth.accessToken)
        XCTAssertEqual(auth.errorMessage?.contains("boom"), true)
    }

    @MainActor
    func test_oauth_disabledOnServerIsNoOp() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL
        auth.oauthSessionHandler = { _ in URL(string: "app.immich://oauth-callback?code=abc") }

        await auth.startOAuthFlow()

        XCTAssertNil(auth.accessToken)
        XCTAssertEqual(auth.errorMessage, "OAuth is not enabled on this server.")
        XCTAssertEqual(mock.requestCount, 0)
    }

    // MARK: - Multi-server / multi-account (P5)

    private func makeLoginAccount(url: String = "https://photos.example.com", email: String = "alice@example.com", name: String = "Alice", userId: String = "u1") -> SavedAccount {
        SavedAccount(url: url, email: email, name: name, userId: userId, isAdmin: false)
    }

    private func seedSavedAccounts(_ accounts: [SavedAccount], defaults: UserDefaults) {
        defaults.set(try! JSONEncoder.immich.encode(accounts), forKey: AuthViewModel.serverListDefaultsKey)
    }

    @MainActor
    func test_login_addsAccountToSavedWithPerAccountToken() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "jwt", userId: "u1", userEmail: "alice@example.com", name: "Alice",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        await auth.login(email: "alice@example.com", password: "secret")

        XCTAssertEqual(auth.savedAccounts.count, 1)
        XCTAssertEqual(auth.savedAccounts.first?.email, "alice@example.com")
        let accountID = SavedAccount.makeID(url: "https://photos.example.com", email: "alice@example.com", userId: "u1")
        XCTAssertEqual(keychain.getToken(for: accountID), "jwt", "token must be stored per-account")
    }

    @MainActor
    func test_login_sameAccountDedupsRegistry() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "jwt2", userId: "u1", userEmail: "alice@example.com", name: "Alice",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        await auth.login(email: "alice@example.com", password: "s1")
        await auth.login(email: "alice@example.com", password: "s2")

        XCTAssertEqual(auth.savedAccounts.count, 1, "same account must be upserted, not duplicated")
    }

    @MainActor
    func test_multipleAccountsSameServer_coexist() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: MockImmichClient(), keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        _ = auth.baseURL

        let alice = makeLoginAccount(email: "alice@example.com", userId: "u1")
        let bob = makeLoginAccount(email: "bob@example.com", userId: "u2")
        keychain.saveToken("alice-jwt", for: alice.id)
        keychain.saveToken("bob-jwt", for: bob.id)
        seedSavedAccounts([alice, bob], defaults: defaults)

        let restored = AuthViewModel(client: MockImmichClient(), keychain: keychain, defaults: defaults)
        XCTAssertEqual(restored.savedAccounts.count, 2)
        XCTAssertNotEqual(alice.id, bob.id, "two accounts on the same URL must have distinct ids")
    }

    @MainActor
    func test_switchToAccount_restoresTokenAndIdentity() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let alice = makeLoginAccount(email: "alice@example.com", userId: "u1")
        let bob = SavedAccount(url: "https://photos.example.com", email: "bob@example.com", name: "Bob", userId: "u2", isAdmin: true)
        keychain.saveToken("alice-jwt", for: alice.id)
        keychain.saveToken("bob-jwt", for: bob.id)
        seedSavedAccounts([alice, bob], defaults: defaults)

        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        // Act as Alice first.
        auth.serverURLString = "https://photos.example.com"
        auth.userEmail = "alice@example.com"
        auth.userName = "Alice"
        auth.userId = "u1"
        auth.accessToken = "alice-jwt"

        await auth.switchToAccount(bob)

        XCTAssertEqual(auth.accessToken, "bob-jwt")
        XCTAssertEqual(auth.userEmail, "bob@example.com")
        XCTAssertEqual(auth.userName, "Bob")
        XCTAssertEqual(auth.userId, "u2")
        XCTAssertTrue(auth.isAdmin)
        XCTAssertEqual(mock.configuredToken, "bob-jwt")
        XCTAssertEqual(mock.configuredBaseURL?.absoluteString, "https://photos.example.com")
        XCTAssertTrue(auth.isAuthenticated)
    }

    @MainActor
    func test_switchToAccount_missingToken_resetsSessionWithURLPrefilled() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let ghost = makeLoginAccount(email: "ghost@example.com", userId: "u9")
        seedSavedAccounts([ghost], defaults: defaults)

        let auth = AuthViewModel(client: MockImmichClient(), keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        auth.accessToken = "current-jwt"

        await auth.switchToAccount(ghost)

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertEqual(auth.serverURLString, "https://photos.example.com", "URL pre-filled for re-login")
    }

    @MainActor
    func test_switchToAccount_invalidToken_resetsSession() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let bob = makeLoginAccount(email: "bob@example.com", userId: "u2")
        keychain.saveToken("stale-jwt", for: bob.id)
        seedSavedAccounts([bob], defaults: defaults)

        let mock = MockImmichClient()
        mock.validateError = APIError.unauthorized
        let auth = AuthViewModel(client: mock, keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        auth.accessToken = "current-jwt"

        await auth.switchToAccount(bob)

        XCTAssertFalse(auth.isAuthenticated, "rejected token must reset the session")
        XCTAssertEqual(auth.serverURLString, "https://photos.example.com")
    }

    @MainActor
    func test_removeSavedAccount_deletesTokenAndRegistry() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let alice = makeLoginAccount(email: "alice@example.com", userId: "u1")
        let bob = makeLoginAccount(email: "bob@example.com", userId: "u2")
        keychain.saveToken("alice-jwt", for: alice.id)
        keychain.saveToken("bob-jwt", for: bob.id)
        seedSavedAccounts([alice, bob], defaults: defaults)

        let auth = AuthViewModel(client: MockImmichClient(), keychain: keychain, defaults: defaults)

        auth.removeSavedAccount(bob)

        XCTAssertEqual(auth.savedAccounts.count, 1)
        XCTAssertEqual(auth.savedAccounts.first?.id, alice.id)
        XCTAssertNil(keychain.getToken(for: bob.id))
        XCTAssertEqual(keychain.getToken(for: alice.id), "alice-jwt", "other account's token untouched")
    }

    @MainActor
    func test_removeActiveAccount_resetsSession() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainStore()
        let alice = makeLoginAccount(email: "alice@example.com", userId: "u1")
        keychain.saveToken("alice-jwt", for: alice.id)
        seedSavedAccounts([alice], defaults: defaults)

        let auth = AuthViewModel(client: MockImmichClient(), keychain: keychain, defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        auth.userEmail = "alice@example.com"
        auth.userId = "u1"
        auth.accessToken = "alice-jwt"

        auth.removeSavedAccount(alice)

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertEqual(auth.savedAccounts.count, 0)
    }

    @MainActor
    func test_addNewServer_resetsAndClearsURL() async {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(client: MockImmichClient(), keychain: MockKeychainStore(), defaults: defaults)
        auth.serverURLString = "https://photos.example.com"
        auth.accessToken = "jwt"

        auth.addNewServer()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertEqual(auth.serverURLString, "")
    }
}
