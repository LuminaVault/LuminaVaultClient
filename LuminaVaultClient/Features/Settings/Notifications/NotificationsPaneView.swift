// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/NotificationsPaneView.swift
//
// HER-179 — Settings → Notifications: per-category opt-out toggles, and the
// one opt-in, the pre-meeting brief.

import LuminaVaultShared
import SwiftUI

struct NotificationsPaneView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: NotificationsPaneViewModel
    /// Settings › Data Access, where calendar sync is turned on. Nil where
    /// no settings shell is hosting; the meeting row then only says so.
    var dataAccess: (() -> DataAccessView)?

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch vm.state {
                    case .loading:
                        ProgressView().tint(palette.primary).padding()
                    case .failed(let message):
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.lvTextMuted)
                            .padding(.horizontal)
                    case .loaded:
                        toggleCard(
                            title: "Daily digest",
                            subtitle: "Curated summary of what Lumina noticed.",
                            isOn: Binding(
                                get: { vm.digestEnabled },
                                set: { newValue in Task { await vm.toggle(.digest, value: newValue) } }
                            )
                        )
                        toggleCard(
                            title: "Nudges",
                            subtitle: "Lumina reaches out when patterns shift.",
                            isOn: Binding(
                                get: { vm.nudgeEnabled },
                                set: { newValue in Task { await vm.toggle(.nudge, value: newValue) } }
                            )
                        )
                        toggleCard(
                            title: "Chat replies",
                            subtitle: "Background chat responses.",
                            isOn: Binding(
                                get: { vm.chatEnabled },
                                set: { newValue in Task { await vm.toggle(.chat, value: newValue) } }
                            )
                        )
                        hermesRunsSection
                        meetingsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Notifications")
        .lvBackground()
        .task { await vm.load() }
    }

    private var header: some View {
        Text("Choose how Lumina reaches you. Disabling a category suppresses the push but the underlying skill still runs.")
            .font(.system(size: 13))
            .foregroundStyle(palette.textSecondary)
    }

    /// Phase 1's two Hermes-run categories. Both became real switches with
    /// Shared 5.6.0, which gave `/v1/me/apns-categories` fields for the M119
    /// columns the server was already honouring.
    private var hermesRunsSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text("HERMES RUNS")
                .lvFont(.kicker)
                .kerning(0.8)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, LVSpacing.sm)

            toggleCard(
                title: "Approval requests",
                subtitle: "Hermes asks before it runs a tool. Answer straight from the notification.",
                isOn: Binding(
                    get: { vm.approvalEnabled },
                    set: { newValue in Task { await vm.toggle(.approval, value: newValue) } }
                )
            )
            toggleCard(
                title: "Run results",
                subtitle: "A run you started finished, failed or was stopped.",
                isOn: Binding(
                    get: { vm.runCompletedEnabled },
                    set: { newValue in Task { await vm.toggle(.runCompleted, value: newValue) } }
                )
            )

            // Turning approvals off does not abandon the run: it waits for an
            // answer given in the app, so say that rather than let someone
            // think a paused agent is a stuck one.
            Text("With approvals off, a run that needs a decision waits for you in Agent Runs.")
                .lvFont(.caption)
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    /// The opt-in pre-meeting brief. Off by default, and useless without
    /// calendar sync, which the row says when it knows sync is off.
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text("MEETINGS")
                .lvFont(.kicker)
                .kerning(0.8)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, LVSpacing.sm)

            MeetingBriefSettingsRow(
                isOn: Binding(
                    get: { vm.meetingBriefEnabled },
                    set: { newValue in Task { await vm.setMeetingBrief(newValue) } }
                ),
                readiness: vm.calendarReadiness,
                dataAccess: dataAccess
            )
        }
    }

    private func toggleCard(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        NotificationToggleCard(title: title, subtitle: subtitle, isOn: isOn)
    }
}

/// One switch with its title and one line of explanation.
struct NotificationToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @Environment(\.lvPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(palette.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

/// Settings › Notifications › Meeting briefs: the opt-in switch, and — when
/// calendar sync is known to be off — what is missing and the way to turn
/// it on. The switch still works then: the choice is kept for when the
/// calendar starts syncing.
struct MeetingBriefSettingsRow: View {
    static let title = "Meeting briefs"
    static let subtitle = "A quiet note 30 minutes before a meeting, only when you've saved something relevant."

    @Binding var isOn: Bool
    let readiness: CalendarSyncReadiness
    var dataAccess: (() -> DataAccessView)?

    @Environment(\.lvPalette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            NotificationToggleCard(title: Self.title, subtitle: Self.subtitle, isOn: $isOn)
            switch readiness {
            case .consentOff:
                calendarNote("Meeting briefs need calendar sync, which is off.") {
                    if let dataAccess {
                        NavigationLink("Turn on Calendar in Data Access") { dataAccess() }
                    } else {
                        Text("Turn it on in Settings › Data Access.")
                    }
                }
            case .systemAccessOff:
                calendarNote("LuminaVault can't read your calendar, so there's nothing to brief on.") {
                    Button("Allow calendar access in iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .ready, .unknown:
                EmptyView()
            }
        }
    }

    private func calendarNote(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Label {
                Text(text)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(palette.accent)
            }
            action()
                .lvFont(.caption)
                .tint(palette.primary)
        }
        .padding(.horizontal, LVSpacing.xs)
    }
}
