// LuminaVaultClient/LuminaVaultClient/Services/HealthKitTypeMapping.swift
//
// Single source of truth for HealthKit ↔ server event mapping. New metrics
// only need a row here — `HealthKitService` walks `allReadTypes` and
// dispatches each sample through `convert(_:)`.

import Foundation
import HealthKit

/// One row of the HK ↔ server mapping table.
struct HealthKitMetric: Sendable {
    let hkSampleType: HKSampleType
    /// Server `type` field. snake_case, ≤64 chars.
    let serverType: String
    /// Default unit string — overridden per-sample for sleep stages.
    let defaultUnit: String?
    /// Source label written to every event from this metric.
    let source: String
    /// Quantity sample → numeric in `valueNumeric`.
    let quantityUnit: HKUnit?
}

enum HealthKitMetricCatalog {
    /// Read-only types we ask permission for. Extend by adding rows here
    /// + a matching mapping in `HealthKitService.convert`. Sleep is the
    /// only category type — everything else is a quantity.
    static var quantityMetrics: [HealthKitMetric] {
        var rows: [HealthKitMetric] = []
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) {
            rows.append(.init(hkSampleType: t, serverType: "hr_bpm", defaultUnit: "bpm", source: "apple_health", quantityUnit: HKUnit.count().unitDivided(by: .minute())))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            rows.append(.init(hkSampleType: t, serverType: "resting_hr_bpm", defaultUnit: "bpm", source: "apple_health", quantityUnit: HKUnit.count().unitDivided(by: .minute())))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            rows.append(.init(hkSampleType: t, serverType: "hrv_ms", defaultUnit: "ms", source: "apple_health", quantityUnit: .secondUnit(with: .milli)))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) {
            rows.append(.init(hkSampleType: t, serverType: "steps", defaultUnit: "steps", source: "apple_health", quantityUnit: .count()))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            rows.append(.init(hkSampleType: t, serverType: "weight_kg", defaultUnit: "kg", source: "apple_health", quantityUnit: .gramUnit(with: .kilo)))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            rows.append(.init(hkSampleType: t, serverType: "active_kcal", defaultUnit: "kcal", source: "apple_health", quantityUnit: .kilocalorie()))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            rows.append(.init(hkSampleType: t, serverType: "respiratory_rate", defaultUnit: "bpm", source: "apple_health", quantityUnit: HKUnit.count().unitDivided(by: .minute())))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            rows.append(.init(hkSampleType: t, serverType: "spo2_percent", defaultUnit: "percent", source: "apple_health", quantityUnit: .percent()))
        }
        if #available(iOS 16.0, *), let t = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            rows.append(.init(hkSampleType: t, serverType: "wrist_temp_c", defaultUnit: "celsius", source: "apple_health", quantityUnit: .degreeCelsius()))
        }
        return rows
    }

    /// Sleep is a category sample (start/end + value). Handled separately.
    static var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    /// Mindful sessions are also category samples (duration only, no enum value).
    static var mindfulType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .mindfulSession)
    }

    /// Every type the app reads. Pass to `requestAuthorization`.
    static var allReadTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>(quantityMetrics.map(\.hkSampleType))
        if let s = sleepType { set.insert(s) }
        if let m = mindfulType { set.insert(m) }
        return set
    }

    /// Maps an `HKCategoryValueSleepAnalysis` raw to a stable server tag.
    static func sleepStage(rawValue: Int) -> String {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:           return "in_bed"
        case HKCategoryValueSleepAnalysis.awake.rawValue:           return "awake"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return "asleep"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:      return "core"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:      return "deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:       return "rem"
        default:                                                    return "unknown"
        }
    }
}
