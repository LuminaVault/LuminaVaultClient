// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthMetric.swift
import Foundation

/// HER-118 — fixed catalog of the four metrics the dashboard surfaces.
/// `type` matches the server `event_type` taxonomy (`HealthKitTypeMapping`).
enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case heartRate
    case hrv
    case steps

    var id: String { rawValue }

    /// Server `event_type` identifier sent with `GET /v1/health/daily?type=`.
    var serverType: String {
        switch self {
        case .sleep: "sleep_session"
        case .heartRate: "hr_bpm"
        case .hrv: "hrv_ms"
        case .steps: "steps"
        }
    }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .heartRate: "Heart Rate"
        case .hrv: "HRV"
        case .steps: "Steps"
        }
    }

    var unit: String {
        switch self {
        case .sleep: "min"
        case .heartRate: "bpm"
        case .hrv: "ms"
        case .steps: "steps"
        }
    }

    /// Sleep + Steps are accumulators (server sums per day); HR + HRV are
    /// instantaneous (server averages per day). Drives latest-value
    /// derivation in `HealthDashboardViewModel`.
    var usesSumAggregation: Bool {
        switch self {
        case .sleep, .steps: true
        case .heartRate, .hrv: false
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: "moon.fill"
        case .heartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .steps: "figure.walk"
        }
    }
}
