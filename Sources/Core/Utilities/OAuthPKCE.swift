import CryptoKit
import Foundation

/// Client-generated PKCE material for the mobile OAuth flow.
///
/// The provider round-trip happens inside a browser session that does not share
/// the URLSession cookie jar, so `state` and the verifier are generated here and
/// replayed on the callback instead of being read back from cookies — the same
/// contract as the upstream Flutter client (`OAuthService`).
struct OAuthPKCE: Equatable {
    let state: String
    let codeVerifier: String
    let codeChallenge: String

    /// RFC 7636 §4.1 — the verifier is 43–128 unreserved characters; 32 random
    /// bytes encode to 43 base64url characters.
    init() {
        let verifier = Self.randomURLSafeString(byteCount: 32)
        self.state = Self.randomURLSafeString(byteCount: 16)
        self.codeVerifier = verifier
        self.codeChallenge = Self.challenge(for: verifier)
    }

    /// `BASE64URL(SHA256(verifier))` without padding, as Immich encodes it.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// base64url without padding — the alphabet encoded parameters use.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
