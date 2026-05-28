// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthEmptyState.swift
import SwiftUI

/// HER-118 — empty-state surface for the health dashboard. Renders when
/// HealthKit permission is denied/not-determined OR all four metrics have
/// no samples in the rolling 7-day window. CTA triggers the
/// HealthKitCoordinator authorization request via the view model.
struct HealthEmptyState: View {
    let permissionState: HealthDashboardViewModel.PermissionState
    var onConnect: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(titleText)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if permissionState != .granted {
                Button {
                    Task { await onConnect() }
                } label: {
                    Text("Connect HealthKit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var titleText: String {
        switch permissionState {
        case .denied:
            return "HealthKit access denied"
        case .notDetermined, .unknown:
            return "Let Lumina see your health signals"
        case .granted:
            return "No samples yet"
        }
    }

    private var bodyText: String {
        switch permissionState {
        case .denied:
            return "Re-enable HealthKit in Settings to surface your Sleep, Heart Rate, HRV, and Steps trends here."
        case .notDetermined, .unknown:
            return "Connect HealthKit so Hermes can correlate your sleep with your notes — Sleep, HR, HRV, and Steps land here as soon as you do."
        case .granted:
            return "Your dashboard fills in as new samples sync from Apple Health."
        }
    }
}
