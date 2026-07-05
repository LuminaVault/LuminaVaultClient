import CryptoKit
import Foundation
import OSLog

/// Audit I3 — TLS certificate pinning for the managed API host.
///
/// Pins the **CA certificates** (ISRG Root X2 + the Let's Encrypt YE1 intermediate),
/// not the 90-day leaf, so routine renewals don't brick the app while a rogue
/// public CA still can't MITM the managed host. Pinning is scoped to the managed
/// host only: BYO / Tailscale / localhost hosts fall through to default trust
/// evaluation (they're user-chosen and often self-signed). If the pin set is ever
/// empty the delegate also falls through — pinning can never harden into a brick.
///
/// Pins are full-certificate SHA-256 (matches `SecCertificateCopyData` exactly, no
/// SPKI ASN.1 reconstruction). To rotate: recompute with
/// `openssl s_client -connect <host>:443 -showcerts | openssl x509 -outform der | shasum -a 256`
/// for the new CA and add it below (add the new pin BEFORE removing the old).
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    /// Host whose chain must contain a pinned CA. Derived from the build's API base URL.
    private let pinnedHost: String?

    /// SHA-256 of the pinned CA certificates' DER (hex, lowercase).
    /// [0] ISRG Root X2 (durable anchor) · [1] Let's Encrypt YE1 intermediate (backup).
    private static let pinnedCertSHA256: Set<String> = [
        "ee5f7abd6981bb0255632cd8f49283451b4b18844d12040b44ee00f07b8fe2c6",
        "a2372d06431e9716365eeed47ec020351497d182fcc038e457e58168a03cac07"
    ]

    private static let log = Logger(subsystem: "com.lumina.fernando", category: "tls-pinning")

    init(pinnedHost: String?) {
        self.pinnedHost = pinnedHost
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Only pin the managed host; anything else uses default trust evaluation.
        guard let pinnedHost, !Self.pinnedCertSHA256.isEmpty,
              challenge.protectionSpace.host.caseInsensitiveCompare(pinnedHost) == .orderedSame
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1) The chain must still pass the system's own validation (expiry, name, trust root).
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            Self.log.error("pinned host \(pinnedHost, privacy: .public) failed system trust evaluation")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2) …AND some certificate in the presented chain must be a pinned CA.
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        for cert in chain {
            let der = SecCertificateCopyData(cert) as Data
            let digest = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
            if Self.pinnedCertSHA256.contains(digest) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }

        Self.log.error("pinned host \(pinnedHost, privacy: .public) presented a chain with no pinned CA — blocking (possible MITM)")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

extension URLSession {
    /// The one host these LE-root pins are valid for. Pinning applies ONLY when the
    /// build actually targets it — debug/localhost and BYO/self-host users (different
    /// host, often a non-LE cert) fall through to default trust so they can't be bricked.
    private static let managedHost = "api.luminavault.fyi"

    /// Shared session that pins the managed API host. Used by the app's HTTP + streaming
    /// clients; tests keep injecting `.shared` (no pinning) unchanged.
    static let lvPinned: URLSession = {
        let pinnedHost = Config.apiBaseURL.host == managedHost ? managedHost : nil
        let delegate = CertificatePinningDelegate(pinnedHost: pinnedHost)
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }()
}
