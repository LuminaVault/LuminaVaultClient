// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/MuseRunDetails.swift
//
// What used to be `ChatStatusStrip`'s expanded half, now folded under the
// Muse header's name pill.
//
// The strip's one-line summary became the header's status line. Its detail
// (route, tokens, cost, context, compare, escalate) is worth having but not
// worth permanent screen space, so it opens from the pill. The multi-model
// mode, which lost its navigation-bar slot when the header replaced the
// toolbar, sits here with the rest of what a turn runs on.

import LuminaVaultShared
import SwiftUI

struct MuseRunDetails: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Bindable var viewModel: ChatViewModel
    let onOpenComparison: (ParallelChatExecution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                MultiModelModeControl(
                    isEnabled: $viewModel.multiModelEnabled,
                    strategy: $viewModel.multiModelStrategy,
                    isStreaming: viewModel.isStreaming
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
                if let reading = contextReading {
                    ChatContextGauge(reading: reading)
                }
            }

            if hasRouteContent {
                HStack(spacing: LVSpacing.sm) {
                    LVIconView(summaryIcon, size: 13, tint: palette.accent)
                    Text(summaryText)
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if viewModel.routeUsage == nil, viewModel.routingEvent != nil {
                        ProgressView().controlSize(.mini)
                    }
                }
            } else {
                Text("No route yet — send a message to see which model answers.")
                    .lvFont(.microTag)
                    .foregroundStyle(palette.textSecondary)
            }

            detail
        }
        .padding(LVSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LVMuse.cardRadius, style: .continuous)
                .fill(palette.muse(scheme).agentBubble)
        )
    }

    private var hasRouteContent: Bool {
        viewModel.fallbackNotice != nil
            || viewModel.routingEvent != nil
            || viewModel.parallelExecution != nil
    }

    private var contextReading: ChatContextGauge.Reading? {
        ChatContextGauge.Reading.make(routing: viewModel.routingEvent, usage: viewModel.routeUsage)
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

    @ViewBuilder
    private var detail: some View {
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
        if let dropped = contextReading?.droppedPhrase {
            Text(dropped)
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

/// Caps a header tray at `maxHeight` and scrolls past it. Measures the
/// content instead of letting the `ScrollView` take whatever it is offered,
/// so a one-row trail costs one row of inset rather than the full cap.
struct MuseHeaderTray<Content: View>: View {
    var maxHeight: CGFloat = 240
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
    }
}
