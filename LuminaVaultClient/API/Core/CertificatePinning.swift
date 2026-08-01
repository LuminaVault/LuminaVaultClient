import CryptoKit
import Foundation
import os
import OSLog

// MARK: - Pin failure log

/// Records the most recent pin rejection so the error layer can tell "the
/// pinning delegate killed this request" apart from "the user cancelled a
/// `.task`".
///
/// URLSession reports both as `URLError.cancelled`, and ~19 call sites treat
/// that as benign and return silently. That is exactly how the Let's Encrypt
/// YE1 → YR2 CA rotation black-holed every API call in production with no
/// visible error anywhere: chat rendered the user's message and never replied,
/// the inbox showed "No chats yet", and the Brain tab span forever. A pin
/// rejection is a hard failure and must never be classified as a cancel.
enum PinningFailureLog {
    struct Failure: Sendable {
        let host: String
        let at: Date
        /// Subject summaries of the chain the server actually presented —
        /// the single most useful datum when diagnosing the next rotation.
        let presentedChain: [String]
    }

    /// `OSAllocatedUnfairLock` rather than an `actor`: `isBenignCancellation`
    /// is a synchronous classifier called from `catch` blocks that cannot await.
    private static let storage = OSAllocatedUnfairLock<[String: Failure]>(initialState: [:])

    /// How long a rejection stays correlated with an in-flight request. The
    /// delegate cancels the challenge immediately before the task fails, so
    /// this only has to cover that one hop.
    static let correlationWindow: TimeInterval = 5

    static func record(host: String, presentedChain: [String], at: Date = Date()) {
        let failure = Failure(host: host, at: at, presentedChain: presentedChain)
        storage.withLock { $0[host.lowercased()] = failure }
    }

    static func recentFailure(for host: String, now: Date = Date()) -> Failure? {
        storage.withLock { store in
            guard let failure = store[host.lowercased()] else { return nil }
            return now.timeIntervalSince(failure.at) <= correlationWindow ? failure : nil
        }
    }

    /// True when *any* host was rejected inside the window. Error paths that
    /// have already lost the URL by classification time use this form.
    static func hasRecentFailure(now: Date = Date()) -> Bool {
        storage.withLock { store in
            store.values.contains { now.timeIntervalSince($0.at) <= correlationWindow }
        }
    }

    static func reset() {
        storage.withLock { $0.removeAll() }
    }
}

// MARK: - Pinning delegate

/// Audit I3 — TLS certificate pinning for the managed API host.
///
/// Pins the **CA public keys** (SubjectPublicKeyInfo), not the 90-day leaf, so
/// routine renewals don't brick the app while a rogue public CA still can't
/// MITM the managed host. Pinning is scoped to the managed host only: BYO /
/// Tailscale / localhost hosts fall through to default trust evaluation
/// (they're user-chosen and often self-signed).
///
/// ## Why SPKI and not full-certificate DER
///
/// This file used to hash the whole certificate DER. A CA that reissues with
/// the *same key* produces different DER, so those pins broke on a routine
/// reissue; the SubjectPublicKeyInfo survives it. The old DER hashes are still
/// accepted as a second form so no device regresses during rollout.
///
/// ## Why there is an expiry
///
/// The predecessor of this file pinned the retired YE1 / ISRG Root X2
/// hierarchy. Let's Encrypt moved the host to YR2 / ISRG Root YR, no pin
/// matched, and every request from every shipped build was cancelled — with no
/// recovery path short of an App Store update. `pinsValidUntil` bounds that
/// blast radius: past the date, a stale build degrades to ordinary system trust
/// instead of black-holing itself.
///
/// ## Rotating the pins
///
/// ```
/// openssl s_client -connect api.luminavault.fyi:443 -servername api.luminavault.fyi -showcerts \
///   | openssl x509 -noout -pubkey \
///   | openssl pkey -pubin -outform der \
///   | shasum -a 256
/// ```
///
/// Add the new pin **before** removing the old one, push `pinsValidUntil`
/// forward, and update `CertificatePinningTests` — that test compares the pin
/// set against the live chain and is what catches the next rotation.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    /// Resolves the host that must present a pinned CA, evaluated **per
    /// challenge**.
    ///
    /// The previous design captured this once in a `static let`, so a process
    /// whose first HTTP call happened while `BackendMode` was `.localhost` got
    /// `pinnedHost == nil` and ran unpinned for its entire lifetime — even
    /// after the user switched back to hosted in Settings.
    private let resolvePinnedHost: @Sendable () -> String?

    /// SHA-256 of the pinned CAs' **SubjectPublicKeyInfo** DER (hex, lowercase).
    /// All three are RSA; see `rsaSPKIHeaders` for the reconstruction.
    static let pinnedSPKISHA256: Set<String> = [
        // Let's Encrypt YR2 intermediate (RSA-2048) — issues the current leaf.
        // Valid Sep 2025 – Sep 2028.
        "9d637b3d27a9e570d07607b9ccadb80a70915c7af72afce12841b1b1da825fd1",
        // ISRG Root YR (RSA-4096) — issues YR2. Valid May 2026 – Sep 2032.
        "7e4e8838a8add6295de7ae3b047d3aba3488ab95db0a0aa56d897a00d8618bcf",
        // ISRG Root X1 (RSA-4096) — cross-signs Root YR, and is the anchor the
        // system trust store actually terminates on. Valid to 2035.
        "0b9fa5a59eed715c26c1020c711b4f6ec42d58b0015e14337a39dad301c5afc3"
    ]

    /// Legacy full-certificate DER hashes, retained as a second accepted form.
    /// Neither is in the current chain (they target the retired YE1 / Root X2
    /// hierarchy); they cost one comparison and guarantee no device is worse
    /// off than before this change.
    static let pinnedCertSHA256: Set<String> = [
        "ee5f7abd6981bb0255632cd8f49283451b4b18844d12040b44ee00f07b8fe2c6",
        "a2372d06431e9716365eeed47ec020351497d182fcc038e457e58168a03cac07"
    ]

    /// Past this date the pin set is presumed stale and pinning falls back to
    /// system trust. A build that outlives its pins degrades to default TLS —
    /// it can never black-hole the app the way the YE1 → YR2 rotation did.
    /// 2027-06-01, roughly a year before the YR2 intermediate expires.
    static let pinsValidUntil = Date(timeIntervalSince1970: 1_811_808_000)

    /// ASN.1 `AlgorithmIdentifier` prefixes that turn the PKCS#1 `RSAPublicKey`
    /// returned by `SecKeyCopyExternalRepresentation` back into a full
    /// SubjectPublicKeyInfo. Keyed by `SecKeyGetBlockSize` (modulus bytes).
    ///
    /// Only the two sizes present in the pinned chain are listed, and both were
    /// verified byte-exact against the live certificates. An unlisted size (or
    /// an EC key, for which `SecKeyCopyExternalRepresentation` returns an X9.63
    /// point rather than PKCS#1) yields no SPKI digest and falls through to the
    /// DER comparison.
    private static let rsaSPKIHeaders: [Int: Data] = [
        // RSA-2048
        256: Data([
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]),
        // RSA-4096
        512: Data([
            0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
        ])
    ]

    private static let log = Logger(subsystem: "com.lumina.fernando", category: "tls-pinning")

    /// Emitted at most once per process so an expired pin set is visible in
    /// Console.app without spamming a line per request.
    private static let expiryNoticeOnce = OSAllocatedUnfairLock(initialState: false)

    init(resolvePinnedHost: @escaping @Sendable () -> String?) {
        self.resolvePinnedHost = resolvePinnedHost
    }

    /// Convenience for tests and for callers that already know the host.
    convenience init(pinnedHost: String?) {
        self.init(resolvePinnedHost: { pinnedHost })
    }

    // MARK: Digests

    /// SHA-256 of a certificate's SubjectPublicKeyInfo DER, or nil when the key
    /// type isn't one we can reconstruct (see `rsaSPKIHeaders`).
    static func spkiSHA256(for certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
              let pkcs1 = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let header = rsaSPKIHeaders[SecKeyGetBlockSize(key)]
        else { return nil }
        return hex(SHA256.hash(data: header + pkcs1))
    }

    /// SHA-256 of a certificate's full DER — the legacy pin form.
    static func certificateSHA256(for certificate: SecCertificate) -> String {
        hex(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when any certificate in the chain is a pinned CA, by either form.
    static func chainContainsPinnedCA(_ chain: [SecCertificate]) -> Bool {
        chain.contains { cert in
            if let spki = spkiSHA256(for: cert), pinnedSPKISHA256.contains(spki) { return true }
            return pinnedCertSHA256.contains(certificateSHA256(for: cert))
        }
    }

    static func pinsAreExpired(now: Date = Date()) -> Bool {
        now > pinsValidUntil
    }

    // MARK: URLSessionDelegate

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
        guard let pinnedHost = resolvePinnedHost(),
              !Self.pinnedSPKISHA256.isEmpty || !Self.pinnedCertSHA256.isEmpty,
              challenge.protectionSpace.host.caseInsensitiveCompare(pinnedHost) == .orderedSame
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Stale pin set → degrade to system trust rather than brick the build.
        if Self.pinsAreExpired() {
            Self.noteExpiryOnce(host: pinnedHost)
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1) The chain must still pass the system's own validation (expiry, name, trust root).
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            Self.log.error("pinned host \(pinnedHost, privacy: .public) failed system trust evaluation")
            PinningFailureLog.record(host: pinnedHost, presentedChain: [])
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2) …AND some certificate in the presented chain must be a pinned CA.
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        if Self.chainContainsPinnedCA(chain) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        let subjects = chain.map {
            (SecCertificateCopySubjectSummary($0) as String?) ?? "<unknown>"
        }
        Self.log.error(
            """
            pinned host \(pinnedHost, privacy: .public) presented a chain with no pinned CA — \
            blocking (possible MITM). presented: \(subjects.joined(separator: " ← "), privacy: .public)
            """
        )
        PinningFailureLog.record(host: pinnedHost, presentedChain: subjects)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private static func noteExpiryOnce(host: String) {
        let shouldLog = expiryNoticeOnce.withLock { alreadyLogged -> Bool in
            guard !alreadyLogged else { return false }
            alreadyLogged = true
            return true
        }
        guard shouldLog else { return }
        log.notice(
            """
            pin set for \(host, privacy: .public) is past pinsValidUntil — \
            falling back to system trust. Rotate the pins and ship an update.
            """
        )
    }
}

extension URLSession {
    /// The one host these Let's Encrypt pins are valid for. Pinning applies ONLY
    /// when the app is actually targeting it — debug/localhost and BYO/self-host
    /// users (different host, often a non-LE cert) fall through to default trust
    /// so they can't be bricked.
    static let lvManagedHost = "api.luminavault.fyi"

    /// Shared session that pins the managed API host. Used by the app's HTTP +
    /// streaming clients; tests keep injecting `.shared` (no pinning) unchanged.
    ///
    /// The session is still a singleton, but the delegate now re-reads
    /// `Config.apiBaseURL` on every challenge, so a mid-session BackendMode flip
    /// no longer leaves the process permanently unpinned.
    static let lvPinned: URLSession = {
        let delegate = CertificatePinningDelegate(resolvePinnedHost: {
            Config.apiBaseURL.host == lvManagedHost ? lvManagedHost : nil
        })
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }()
}
