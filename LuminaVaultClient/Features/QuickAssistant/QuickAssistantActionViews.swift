// LuminaVaultClient/LuminaVaultClient/Features/QuickAssistant/QuickAssistantActionViews.swift
//
// What the assistant did, shown on the card: a chip for each thing it did, a
// confirm card for each thing it wants to do and asks about first, a button for
// a permission it needs, and the route an `openScreen` takes.
//
// Every word on a card comes from the server's `summary` or resolution message,
// never from the model's reply. Unknown action kinds and screens render nothing.
import LuminaVaultShared
import SwiftUI

// MARK: - Route

/// Where an `openScreen` goes. `MainTabView` carries it out.
enum QuickAssistantRoute: Equatable {
    case tab(MainTabView.AppTab)
    case settings
    /// Data Access, by way of Settings: the one place the app presents it.
    case dataAccess
    case deepLink(APNSDeepLink)
    /// Nowhere: an unknown screen, or a memory the server named no id for.
    case none

    static func resolve(_ screen: AssistantScreenDTO, memoryID: UUID?) -> QuickAssistantRoute {
        switch screen {
        case .home: .tab(.home)
        case .spaces: .tab(.workspaces)
        case .ai: .tab(.think)
        case .brain: .tab(.brain)
        case .insights: .tab(.reflect)
        case .settings: .settings
        case .dataAccess: .dataAccess
        case .brief: .deepLink(.brief)
        case .learned: .deepLink(.learned)
        case .memory: memoryID.map { .deepLink(.memory(id: $0)) } ?? .none
        case .unknown: .none
        }
    }
}

// MARK: - State

extension AssistantActionDTO {
    /// A forget-memory confirm. The DTO carries no kind of action beyond
    /// `needsConfirm`, so the server's own summary wording is the only signal; the
    /// server writes it (`QuickAssistantToolRunner.proposeForget`), never the model.
    var isDestructive: Bool {
        kind == .needsConfirm && summary.hasPrefix("Forget this memory")
    }
}

/// What a confirm card shows and allows.
enum QuickAssistantConfirmState: Equatable {
    /// Waiting for a tap. `error` is a failed attempt; the card stays actionable.
    case ask(error: String?)
    case resolving
    /// Any server answer, including a status this build does not know.
    case finished(AssistantActionResolutionDTO)

    /// Disabled only while resolving and after a result. Never from `expiresAt`:
    /// the server answers `.expired`, and a wrong device clock must not kill a
    /// valid card.
    var buttonsEnabled: Bool {
        if case .ask = self { return true }
        return false
    }

    @MainActor
    static func of(_ action: AssistantActionDTO, in model: QuickAssistantModel) -> QuickAssistantConfirmState {
        if let resolution = model.resolutions[action.id] { return .finished(resolution) }
        if model.resolving.contains(action.id) { return .resolving }
        return .ask(error: model.actionErrors[action.id])
    }
}

// MARK: - Actions

/// The chips, cards and rows for a turn's actions.
struct QuickAssistantActions: View {
    let model: QuickAssistantModel
    let onRoute: (QuickAssistantRoute) -> Void

    private var chips: [AssistantActionDTO] { model.actions.filter { $0.kind == .done } }
    /// Confirm and permission cards, in the order the server sent them.
    private var cards: [AssistantActionDTO] {
        model.actions.filter { $0.kind == .needsConfirm || $0.kind == .needsPermission }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            if !chips.isEmpty {
                LVFlowLayout(spacing: LVSpacing.sm) {
                    ForEach(chips, id: \.id) { QuickAssistantChip(summary: $0.summary) }
                }
            }
            ForEach(cards, id: \.id) { action in
                if action.kind == .needsConfirm {
                    QuickAssistantConfirmCard(action: action, model: model)
                } else {
                    QuickAssistantPermissionCard(summary: action.summary) { onRoute(.dataAccess) }
                }
            }
            if let route = model.heldScreenRoute,
               let opening = model.actions.first(where: { $0.kind == .openScreen })
            {
                QuickAssistantScreenRow(summary: opening.summary) { onRoute(route) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Something the assistant did. Read out as one phrase.
struct QuickAssistantChip: View {
    let summary: String
    @Environment(\.lvPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.xs) {
            LVIconView(.checkmarkCircleFill, size: 14, tint: palette.primary)
            Text(summary)
                .lvFont(.footnote)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, LVSpacing.xs + 2)
        .padding(.horizontal, LVSpacing.md)
        .background(palette.surface, in: .rect(cornerRadius: LVRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Done: \(summary)")
    }
}

/// An action that waits for the user. The summary is read before the buttons, and
/// the result is announced when it arrives.
struct QuickAssistantConfirmCard: View {
    let action: AssistantActionDTO
    let model: QuickAssistantModel

    @Environment(\.lvPalette) private var palette

    private var state: QuickAssistantConfirmState { .of(action, in: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text(action.summary)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(2)

            switch state {
            case let .finished(resolution):
                result(resolution)
            case let .ask(error):
                if let error {
                    Text(error)
                        .lvFont(.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            case .resolving:
                buttons
            }
        }
        .padding(LVSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: LVRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: state) { _, new in
            if case let .finished(resolution) = new {
                AccessibilityNotification.Announcement(resolution.message).post()
            }
        }
    }

    /// Side by side when they fit, stacked at accessibility sizes, so neither is clipped.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LVSpacing.sm) {
                cancelButton
                confirmButton
            }
            VStack(spacing: LVSpacing.sm) {
                confirmButton
                cancelButton
            }
        }
        .disabled(!state.buttonsEnabled)
        .accessibilitySortPriority(1)
    }

    private var confirmButton: some View {
        Button {
            Task { await model.confirm(action) }
        } label: {
            Text("Confirm")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget)
        }
        .buttonStyle(.lvProminent(destructive: action.isDestructive))
        .controlSize(.large)
    }

    private var cancelButton: some View {
        Button {
            Task { await model.cancel(action) }
        } label: {
            Text("Cancel")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func result(_ resolution: AssistantActionResolutionDTO) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.xs) {
            LVIconView(Self.icon(for: resolution.status), size: 14, tint: Self.tint(for: resolution.status, palette))
            Text(resolution.message)
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private static func icon(for status: AssistantActionStatusDTO) -> LVIcon {
        switch status {
        case .confirmed: .checkmarkCircleFill
        case .cancelled: .xmarkCircleFill
        case .failed: .exclamationmarkTriangleFill
        case .expired: .clockBadgeExclamationmark
        case .alreadyResolved, .unknown: .clock
        }
    }

    private static func tint(for status: AssistantActionStatusDTO, _ palette: LVPalette) -> Color {
        status == .confirmed ? palette.primary : palette.textSecondary
    }
}

/// An action the server could not take until the user allows it in Data Access.
struct QuickAssistantPermissionCard: View {
    let summary: String
    let open: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text(summary)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(2)
            Button(action: open) {
                Text("Open Data Access")
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget)
            }
            .buttonStyle(.lvProminent)
            .controlSize(.large)
            .accessibilitySortPriority(1)
        }
        .padding(LVSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: LVRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A screen the assistant opened that waited because a card needs an answer first.
struct QuickAssistantScreenRow: View {
    let summary: String
    let open: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Button(action: open) {
            HStack(spacing: LVSpacing.sm) {
                Text(summary)
                    .lvFont(.footnote)
                    .foregroundStyle(palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                LVIconView(.chevronRight, size: 12, tint: palette.primary)
            }
            .frame(minHeight: LVSize.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
