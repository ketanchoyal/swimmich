import Foundation
import Security

/// URLSession delegate that accepts self-signed/invalid TLS certificates for
/// hosts the user has explicitly trusted (P5 selfsigned-cert).
///
/// Flow per serverTrust challenge:
/// 1. Standard evaluation (`SecTrustEvaluateWithError`) — trusted chains pass.
/// 2. On failure, if the host is in `TrustedServerStore`, anchor the server's
///    own certificate chain and re-evaluate — the certificate becomes its own
///    trust anchor, exactly the iOS "Trust this certificate" semantics.
/// 3. Anything else → cancel the challenge.
final class TrustEvaluatingURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let trustStore: TrustedServerStore

    init(trustStore: TrustedServerStore) {
        self.trustStore = trustStore
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Step 1: default evaluation.
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        // Step 2: explicit user trust — anchor the server's own chain.
        let host = challenge.protectionSpace.host
        guard trustStore.contains(host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        guard !certificates.isEmpty else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        SecTrustSetAnchorCertificates(serverTrust, certificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
