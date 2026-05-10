// LuminaVaultClient/LuminaVaultClient/Services/HealthKitService.swift
//
// HealthKit → LuminaVault server bridge.
//
// Foreground sync: `requestAuthorization` (once per install), `syncAll`
// runs an HKAnchoredObjectQuery per type, batches the deltas, and POSTs
// `/v1/health`. Anchors are persisted in UserDefaults so reruns are
// incremental.
//
// Background sync: `enableBackgroundDelivery` registers an HKObserverQuery
// per type. When iOS wakes the app with new samples, the observer's
// completion handler runs `syncAll` and acks. Pair with an
// `HKHealthStore.handleAuthorizationForExtension`-style entitlement +
// `processing` UIBackgroundMode.
//
// Add a metric: extend `HealthKitMetricCatalog.quantityMetrics`. Sleep
// and mindful are special-cased because they're category samples.

import Foundation
import HealthKit
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "healthkit")

actor HealthKitService {
    private let healthStore: HKHealthStore
    private let httpClient: BaseHTTPClient
    private let anchorStore: AnchorStore

    init(httpClient: BaseHTTPClient, anchorStore: AnchorStore = .shared) {
        self.healthStore = HKHealthStore()
        self.httpClient = httpClient
        self.anchorStore = anchorStore
    }

    // MARK: - Public surface

    /// Returns false when HealthKit is unavailable (iPad without sensors,
    /// simulator without a valid scheme, etc.).
    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// One-shot consent prompt. Safe to call repeatedly — HealthKit
    /// remembers the previous answer and only re-prompts for new types.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        let read = HealthKitMetricCatalog.allReadTypes
        try await healthStore.requestAuthorization(toShare: [], read: read)
    }

    /// Foreground pull. Walks every configured type, fetches deltas since
    /// the last anchor, batches the result, POSTs once. Anchors only
    /// persist after a successful POST so a network blip just retries
    /// the same window next time.
    @discardableResult
    func syncAll() async throws -> Int {
        guard isAvailable else { return 0 }
        var batch: [HealthEventInput] = []
        var newAnchors: [String: HKQueryAnchor] = [:]

        for metric in HealthKitMetricCatalog.quantityMetrics {
            let (samples, anchor) = try await anchoredQuery(
                type: metric.hkSampleType,
                anchor: anchorStore.anchor(for: metric.hkSampleType.identifier)
            )
            for sample in samples {
                if let q = sample as? HKQuantitySample, let unit = metric.quantityUnit {
                    batch.append(.init(
                        type: metric.serverType,
                        recordedAt: q.startDate,
                        valueNumeric: q.quantity.doubleValue(for: unit),
                        valueText: nil,
                        unit: metric.defaultUnit,
                        source: metric.source,
                        metadata: Self.metadataFor(quantitySample: q)
                    ))
                }
            }
            if let anchor { newAnchors[metric.hkSampleType.identifier] = anchor }
        }

        if let sleepType = HealthKitMetricCatalog.sleepType {
            let (samples, anchor) = try await anchoredQuery(
                type: sleepType,
                anchor: anchorStore.anchor(for: sleepType.identifier)
            )
            for s in samples {
                guard let cs = s as? HKCategorySample else { continue }
                let durationMinutes = cs.endDate.timeIntervalSince(cs.startDate) / 60.0
                let stage = HealthKitMetricCatalog.sleepStage(rawValue: cs.value)
                let isStage = stage != "in_bed" && stage != "awake" && stage != "unknown"
                batch.append(.init(
                    type: isStage ? "sleep_stage" : "sleep_session",
                    recordedAt: cs.startDate,
                    valueNumeric: durationMinutes,
                    valueText: stage,
                    unit: "minutes",
                    source: "apple_health",
                    metadata: [
                        "stage": stage,
                        "ended_at": ISO8601DateFormatter().string(from: cs.endDate),
                        "uuid": cs.uuid.uuidString
                    ]
                ))
            }
            if let anchor { newAnchors[sleepType.identifier] = anchor }
        }

        if let mindfulType = HealthKitMetricCatalog.mindfulType {
            let (samples, anchor) = try await anchoredQuery(
                type: mindfulType,
                anchor: anchorStore.anchor(for: mindfulType.identifier)
            )
            for s in samples {
                let minutes = s.endDate.timeIntervalSince(s.startDate) / 60.0
                batch.append(.init(
                    type: "mindful_minutes",
                    recordedAt: s.startDate,
                    valueNumeric: minutes,
                    valueText: nil,
                    unit: "minutes",
                    source: "apple_health",
                    metadata: ["uuid": s.uuid.uuidString]
                ))
            }
            if let anchor { newAnchors[mindfulType.identifier] = anchor }
        }

        guard !batch.isEmpty else {
            log.info("no new HealthKit samples")
            return 0
        }

        // Server caps batch at 1000 events; chunk if we have more.
        var pushed = 0
        for chunk in batch.chunked(into: 500) {
            let response = try await httpClient.execute(HealthEndpoints.Ingest(events: chunk))
            pushed += response.inserted
            log.info("synced \(response.inserted) events (\(response.skipped) skipped)")
        }
        // Persist anchors only after the server acked everything.
        for (key, anchor) in newAnchors {
            anchorStore.setAnchor(anchor, for: key)
        }
        return pushed
    }

    /// Subscribe to background updates. Call once on app launch (after
    /// successful auth); HealthKit takes care of waking the app via the
    /// `processing` background mode when new samples arrive.
    func enableBackgroundDelivery() async {
        guard isAvailable else { return }
        for sampleType in HealthKitMetricCatalog.allReadTypes {
            do {
                try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
            } catch {
                log.warning("background delivery failed for \(sampleType.identifier, privacy: .public): \(error.localizedDescription)")
            }
        }
        startObservers()
    }

    func disableBackgroundDelivery() async {
        guard isAvailable else { return }
        for sampleType in HealthKitMetricCatalog.allReadTypes {
            try? await healthStore.disableBackgroundDelivery(for: sampleType)
        }
    }

    // MARK: - Observer queries (background)

    nonisolated private func startObservers() {
        for sampleType in HealthKitMetricCatalog.allReadTypes {
            let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                if let error {
                    log.warning("observer error for \(sampleType.identifier, privacy: .public): \(error.localizedDescription)")
                    completion()
                    return
                }
                Task {
                    do { _ = try await self?.syncAll() }
                    catch { log.warning("background syncAll failed: \(error.localizedDescription)") }
                    completion()
                }
            }
            healthStore.execute(observer)
        }
    }

    // MARK: - Anchored query helper

    private func anchoredQuery(
        type: HKSampleType,
        anchor: HKQueryAnchor?
    ) async throws -> ([HKSample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { cont in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: (samples ?? [], newAnchor))
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private static func metadataFor(quantitySample sample: HKQuantitySample) -> [String: String]? {
        var meta: [String: String] = [:]
        meta["uuid"] = sample.uuid.uuidString
        meta["ended_at"] = ISO8601DateFormatter().string(from: sample.endDate)
        if let device = sample.device?.name { meta["device"] = device }
        if let bundle = sample.sourceRevision.source.bundleIdentifier {
            meta["bundle_id"] = bundle
        }
        return meta.isEmpty ? nil : meta
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit is not available on this device."
        case .notAuthorized: return "HealthKit access denied."
        }
    }
}

// MARK: - Anchor persistence

/// Stores `HKQueryAnchor` blobs keyed by HK identifier so anchored
/// queries are incremental across launches. UserDefaults is fine here —
/// anchors aren't sensitive and survive app deletion via iCloud sync if
/// the user's UserDefaults is replicated.
final class AnchorStore: @unchecked Sendable {
    static let shared = AnchorStore(defaults: .standard)

    private let defaults: UserDefaults
    private let prefix = "lv.healthkit.anchor."

    init(defaults: UserDefaults) { self.defaults = defaults }

    func anchor(for identifier: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: prefix + identifier) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func setAnchor(_ anchor: HKQueryAnchor, for identifier: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        defaults.set(data, forKey: prefix + identifier)
    }

    func reset() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Array chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
