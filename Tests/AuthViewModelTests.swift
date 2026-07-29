import XCTest
@testable import ImmichSwiftUI

final class AuthViewModelTests: XCTestCase {

    // AC-003: login sends {email,password} to POST /api/auth/login.
    @MainActor
    func test_AC_003_loginSendsCorrectBody() async {
        let mock = MockImmichClient()
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore())
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
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "fake-jwt", userId: "u", userEmail: "t@e.com", name: "T",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.login(email: "t@e.com", password: "secret")
        XCTAssertEqual(keychain.savedToken, "fake-jwt")
        XCTAssertTrue(auth.isAuthenticated)
    }

    // AC-005: logout clears Keychain + isAuthenticated = false.
    @MainActor
    func test_AC_005_logoutClearsKeychainAndIsAuthenticated() async {
        let mock = MockImmichClient()
        mock.loginResponse = LoginResponseDto(
            accessToken: "pre-jwt", userId: "u", userEmail: "t@e.com", name: "T",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
        let keychain = MockKeychainStore()
        let auth = AuthViewModel(client: mock, keychain: keychain)
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
        let mock = MockImmichClient()
        mock.pingError = URLError(.cannotConnectToHost)

        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore())
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

        let mock = MockImmichClient()
        mock.pingResponse = ServerPingResponse(res: "pong")
        let auth = AuthViewModel(client: mock, keychain: MockKeychainStore())
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL

        await auth.connectServer()
        if case .reachable = auth.serverStatus {
            // ok
        } else {
            XCTFail("expected .reachable, got \(auth.serverStatus)")
        }
    }
}
