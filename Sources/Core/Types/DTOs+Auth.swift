import Foundation

// MARK: - OAuth DTOs (P5 oauth)

/// `POST /api/oauth/authorize` — request body (`OAuthConfigDto`).
struct OAuthAuthorizeRequestDto: Codable, Equatable {
    let redirectUri: String
    let state: String
    let codeChallenge: String
}

/// `POST /api/oauth/authorize` — response (`OAuthAuthorizeResponseDto`).
struct OAuthAuthorizeResponseDto: Codable, Equatable {
    let url: String
}

/// `POST /api/oauth/callback` — request body (`OAuthCallbackDto`).
///
/// `state` and `codeVerifier` are sent explicitly: the provider round-trip ran
/// in a browser session, so the server-side cookies set by `authorize` are not
/// necessarily back on this session.
struct OAuthCallbackRequestDto: Codable, Equatable {
    let url: String
    let state: String
    let codeVerifier: String
}
