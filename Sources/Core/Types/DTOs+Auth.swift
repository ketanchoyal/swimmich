import Foundation

// MARK: - OAuth DTOs (P5 oauth)

/// `GET /api/auth/oauth/mobile`
struct OAuthMobileResponseDto: Codable, Equatable {
    let url: String
}

/// `POST /api/auth/oauth/callback`
struct OAuthCallbackRequestDto: Codable, Equatable {
    let url: String
    let redirectUri: String
}

/// `POST /api/auth/oauth/callback`
struct OAuthCallbackResponseDto: Codable, Equatable {
    let accessToken: String
    let isAdmin: Bool
    let name: String
    let email: String
    let profileImagePath: String
    var shouldChangePassword: Bool?
}
