// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/MessageActionRow.swift
//
// Copy / regenerate / edit-and-resend under the newest assistant turn.
//
// These live in a permanently visible row rather than behind the long-press
// context menu. Hover doesn't exist on touch, so a hidden affordance is an
// undiscovered one, and copy and regenerate are the two things people reach
// for most. The context menu stays as the secondary path for older turns.
//
// Copy stays available while a turn is in flight — reading text is never
// destructive. Regenerate and edit are disabled: the stop button already
// covers "I don't want this answer", and offering both races
// `finalizeAssistantTurn`.
import SwiftUI
import UIKit

struct MessageActionRow: View {
    @Environment(\.lvPalette) private var palette
    let message: ChatViewModel.Message
    /// True while a turn is streaming or starting.
    let isBusy: Bool
    let onRegenerate: () -> Void
    /// `nil` when no user turn precedes this answer, which makes
    /// edit-and-resend meaningless.
    let onEdit: (() -> Void)?

    @State private var copyTrigger = 0
    @State private var regenerateTrigger = 0
    @State private var editTrigger = 0

    var body: some View {
        HStack(spacing: 0) {
            actionButton(icon: .docOnDoc, label: "Copy answer") {
                // View-side on purpose: the pasteboard is a UI concern and
                // giving the view model a copy surface would only make it
                // harder to test.
                UIPasteboard.general.string = message.content
                copyTrigger += 1
            }

            actionButton(icon: .arrowClockwise, label: "Regenerate answer", isEnabled: !isBusy) {
                regenerateTrigger += 1
                onRegenerate()
            }

            if let onEdit {
                actionButton(icon: .pencil, label: "Edit and resend", isEnabled: !isBusy) {
                    editTrigger += 1
                    onEdit()
                }
            }

            Spacer(minLength: 0)
        }
        // Routed through `.sensoryFeedback` rather than a feedback generator
        // so the `hapticsEnabled` preference is honoured for free.
        .sensoryFeedback(.impact(weight: .light), trigger: copyTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: regenerateTrigger)
        .sensoryFeedback(.selection, trigger: editTrigger)
    }

    private func actionButton(
        icon: LVIcon,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LVIconView(icon, size: 15, tint: palette.textSecondary.opacity(0.7), label: label)
                .frame(width: LVSize.tapTarget, height: LVSize.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .lvGlowPress()
    }
}
