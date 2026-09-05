// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunDetailView.swift
//
// Hermes Companion Phase 1 — one run, live: the approval prompt, the answer
// as it streams, the event trail, and stop.
//
// The approval card sits at the top and never scrolls away while a run is
// waiting: it is the only thing on this screen that the run is blocked on.

import LuminaVaultShared
import SwiftUI

struct HermesRunDetailView: View {
    @Environment(\.lvPalette) private var palette

    @State var vm: HermesRunDetailViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .toolbar {
            if vm.canStop {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        Task { await vm.stop() }
                    } label: {
                        if vm.isStopping {
                            ProgressView().tint(palette.primary)
                        } else {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    }
                    .disabled(vm.isStopping)
                }
            }
        }
        // One long-lived task owns the SSE connection, so leaving the screen
        // cancels it rather than leaking a stream per visit.
        .task { await vm.follow() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let failure):
            failureState(failure)
        case .loaded:
            loaded
        }
    }

    private func failureState(_ failure: HermesRunsFailure) -> some View {
        VStack(spacing: LVSpacing.md) {
            Text(failure.message)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            if let guidance = failure.guidance {
                Text(guidance)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if failure.isRetryable {
                Button("Try again") { Task { await vm.retry() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(LVSpacing.xl)
    }

    private var loaded: some View {
        VStack(spacing: 0) {
            if let approval = vm.pendingApproval {
                HermesRunApprovalCard(
                    approval: approval,
                    answering: vm.answeringChoice,
                    onChoose: { choice in Task { await vm.approve(choice) } }
                )
                .padding(.horizontal, LVSpacing.base)
                .padding(.top, LVSpacing.md)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    header
                    if !vm.liveMessage.isEmpty { answer }
                    if !vm.trail.isEmpty { trail }
                    if let error = vm.run?.error, !error.isEmpty { runError(error) }
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.vertical, LVSpacing.base)
            }
        }
        .overlay(alignment: .bottom) {
            if let failure = vm.actionError {
                actionErrorBanner(failure)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                HermesRunStatusBadge(status: vm.status)
                if vm.isFollowing, !vm.isTerminal {
                    Text("Live")
                        .lvFont(.microTag)
                        .foregroundStyle(palette.accent)
                }
                Spacer()
                if let started = vm.run?.startedAt {
                    Text(started, format: .relative(presentation: .named))
                        .lvFont(.caption)
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
            Text(vm.run?.prompt ?? "")
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
            if let explanation = vm.status.lvExplanation {
                Text(explanation)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("ANSWER")
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            Text(vm.liveMessage)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LVSpacing.base)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.7)
    }

    private var trail: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("TRAIL")
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            ForEach(vm.trail) { item in
                HermesRunTrailRow(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runError(_ message: String) -> some View {
        Text(message)
            .lvFont(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LVSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .fill(Color.red.opacity(0.10))
            )
    }

    private func actionErrorBanner(_ failure: HermesRunsFailure) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text(failure.message)
                .lvFont(.caption)
                .foregroundStyle(palette.textPrimary)
            if let guidance = failure.guidance {
                Text(guidance)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LVSpacing.md)
        .lvGlassCard(cornerRadius: LVRadius.md, intensity: 0.8)
        .padding(LVSpacing.base)
        .onTapGesture { vm.actionError = nil }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismiss")
    }
}

/// The blocking prompt. Buttons are built from the choices the server sent —
/// Hermes withholds `always` for some commands, and offering it anyway would
/// promise a permission the run cannot grant.
struct HermesRunApprovalCard: View {
    @Environment(\.lvPalette) private var palette
    let approval: HermesRunPendingApprovalDTO
    let answering: HermesApprovalChoice?
    let onChoose: (HermesApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack(spacing: LVSpacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(palette.glowPrimary)
                Text("Hermes needs approval")
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(approval.requestedAt, format: .relative(presentation: .named))
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
            }

            if let command = approval.command, !command.isEmpty {
                Text(command)
                    .lvFont(.mono)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LVSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: LVRadius.sm, style: .continuous)
                            .fill(palette.surface.opacity(0.6))
                    )
            }

            LVFlowLayout(spacing: LVSpacing.sm) {
                ForEach(approval.choices, id: \.self) { choice in
                    HermesApprovalChoiceButton(
                        choice: choice,
                        isAnswering: answering == choice,
                        isDisabled: answering != nil,
                        action: { onChoose(choice) }
                    )
                }
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.focused)
    }

    /// The wire values are terse (`once`, `session`, `always`); a lock-screen
    /// button and a card button should read the same, so both use these.
    static func label(for choice: HermesApprovalChoice) -> String {
        switch choice {
        case .once: return "Allow once"
        case .session: return "Allow this run"
        case .always: return "Always allow"
        case .deny: return "Deny"
        }
    }
}

/// One approval answer. Its own view because the whole card's body could not
/// be type-checked in reasonable time as a single expression.
private struct HermesApprovalChoiceButton: View {
    @Environment(\.lvPalette) private var palette
    let choice: HermesApprovalChoice
    let isAnswering: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.borderedProminent)
        .tint(choice == .deny ? Color.red : palette.primary)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var label: some View {
        if isAnswering {
            ProgressView().tint(palette.textPrimary)
        } else {
            Text(HermesRunApprovalCard.label(for: choice))
                .lvFont(.button)
        }
    }
}

struct HermesRunTrailRow: View {
    @Environment(\.lvPalette) private var palette
    let item: HermesRunTrailItem

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            Image(systemName: item.systemImage)
                .lvFont(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                Text(item.title)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: LVSpacing.sm)
            Text(item.at, format: .dateTime.hour().minute())
                .lvFont(.caption)
                .foregroundStyle(Color.lvTextMuted)
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private var tint: Color {
        switch item.kind {
        case .lifecycle: return palette.textSecondary
        case .tool: return palette.accent
        case .approval: return palette.glowPrimary
        case .failure: return .red
        case .success: return palette.primary
        }
    }
}
