// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatStatusStrip.swift
//
// One row of live execution status, directly above the composer.
//
// This replaces three independent bars that each claimed their own full-width
// slot in the bottom bar — the provider-fallback banner, the Cerberus routing
// indicator, and the multi-model progress button. Three bars meant the
// composer could sit 100pt+ off the keyboard while an answer streamed, and
// each new bar shifted it again mid-typing.
//
// Collapsed, the strip is a single line: the route, plus a token/cost figure
// when the turn has settled. Tapping expands it to the full detail, which is
// where the escalate action and the fallback explanation live — information
// worth having, but not worth permanent screen real estate.
import LuminaVaultShared
import SwiftUI

struct ChatStatusStrip: View {
    @Environment(\.lvPalette) private var palette
    let viewModel: ChatViewModel
    let onOpenComparison: (ParallelChatExecution) -> Void

    @State private var isExpanded = false

    private var hasContent: Bool {
        viewModel.fallbackNotice != nil
            || viewModel.routingEvent != nil
            || viewModel.parallelExecution != nil
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(alignment: .leading, spacing: LVSpacing.sm) {
                    summaryRow
                    if isExpanded {
                        expandedDetail
                    }
                }
                .padding(.horizontal, LVSpacing.md)
                .padding(.vertical, LVSpacing.sm)
                .lvGlassCard(cornerRadius: LVRadius.md, intensity: LVGlow.subtle)
                .padding(.horizontal, LVSpacing.lg)
                .padding(.bottom, LVSpacing.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // The transitions above and inside are inert without an animation in
        // scope. This is the one that drives them.
        .lvAnimation(LVMotion.standard, value: statusIdentity)
    }

    /// Everything the strip renders, folded into one comparable value so a
    /// single `.animation(_:value:)` covers appear, disappear and expand.
    private var statusIdentity: String {
        [
            viewModel.fallbackNotice?.userMessage ?? "",
            viewModel.routingEvent.map(\.profileName) ?? "",
            viewModel.parallelExecution.map { "\($0.id)-\($0.status)" } ?? "",
            viewModel.routeUsage.map { "\($0.tokensIn + $0.tokensOut)" } ?? "",
            isExpanded ? "open" : "shut",
        ].joined(separator: "|")
    }

    // MARK: - Collapsed

    private var summaryRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: LVSpacing.sm) {
                LVIconView(summaryIcon, size: 13, tint: palette.accent)
                Text(summaryText)
                    .lvFont(.microTag)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let usage = viewModel.routeUsage {
                    Text("\(usage.tokensIn + usage.tokensOut) tok")
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                } else if viewModel.routingEvent != nil {
                    ProgressView().controlSize(.mini)
                }
                LVIconView(
                    isExpanded ? .chevronUp : .chevronDown,
                    size: 11,
                    tint: palette.textSecondary
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summaryText)
        .accessibilityHint(isExpanded ? "Collapse execution details" : "Expand execution details")
    }

    private var summaryIcon: LVIcon {
        if viewModel.fallbackNotice != nil {
            return .exclamationmarkTriangleFill
        }
        if viewModel.parallelExecution != nil {
            return .sparkles
        }
        return .arrowTriangle2Circlepath
    }

    private var summaryText: String {
        if let notice = viewModel.fallbackNotice {
            return notice.userMessage
        }
        if let execution = viewModel.parallelExecution {
            return "\(execution.outputs.count) models · \(execution.strategy.rawValue)"
        }
        guard let routing = viewModel.routingEvent else { return "Routing" }
        if let displayLabel = routing.displayLabel, routing.activeRoutes.isEmpty {
            return displayLabel
        }
        if let route = routing.activeRoutes.first {
            return "\(route.provider.rawValue) · \(route.model)"
        }
        return "Selecting model"
    }

    // MARK: - Expanded

    @ViewBuilder
    private var expandedDetail: some View {
        if let routing = viewModel.routingEvent {
            Text(routingHeadline(routing))
                .lvFont(.microTag)
                .foregroundStyle(palette.textSecondary)
        }
        if let usage = viewModel.routeUsage {
            Text(
                "\(usage.tokensIn + usage.tokensOut) tokens · "
                    + (Double(usage.estimatedCostUsdMicros) / 1_000_000).formatted(.currency(code: "USD"))
                    + " · \(usage.latencyMs) ms"
            )
            .lvFont(.microTag)
            .foregroundStyle(palette.textSecondary)
        }
        if let execution = viewModel.parallelExecution {
            Button {
                onOpenComparison(execution)
            } label: {
                Label("Compare answers", systemImage: "square.split.2x1")
                    .lvFont(.microTag)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.accent)
        }
        if viewModel.canEscalateToStrongerModel {
            Button {
                viewModel.escalateToStrongerModel()
            } label: {
                Label("Use stronger model", systemImage: "bolt.fill")
                    .lvFont(.microTag)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.accent)
            .accessibilityHint("Retry the last turn with a higher-capability model")
        }
    }

    private func routingHeadline(_ routing: RouterRoutingEventDTO) -> String {
        if routing.profileName == "BYO Hermes" {
            return "Routing managed by your Hermes"
        }
        return "Auto · \(routing.taskType.rawValue.capitalized) · \(routing.profileName)"
    }
}
