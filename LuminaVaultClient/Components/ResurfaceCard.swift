// LuminaVaultClient/LuminaVaultClient/Components/ResurfaceCard.swift
//
// "To revisit" on Home: one memory worth seeing again, why it is back, and
// four answers. Keep, Soon and Later sit on the card; Never is one tap
// further, behind a menu, because it is the only one that cannot be taken
// back from here. Tapping the memory itself opens it.
//
// The card is a plain view over the queue's state; `ResurfaceQueueViewModel`
// decides what is current and what an answer said.

import LuminaVaultShared
import SwiftUI

struct ResurfaceCard: View {
    /// Nil once the queue has run out while a confirmation finishes showing.
    let item: ResurfaceItemDTO?
    /// Memories left including this one, for "1 of 3".
    let remaining: Int
    let confirmation: String?
    let isPending: Bool
    let errorMessage: String?
    let onOpen: (ResurfaceItemDTO) -> Void
    let onAction: (MemoryReviewAction, ResurfaceItemDTO) -> Void
    /// The confirmation has been up long enough.
    let onConfirmationShown: () -> Void
    /// Off in the Daily review list, where every row would repeat it.
    var showsHeader = true

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            if showsHeader {
                header
            }
            if let item {
                memory(item)
                actions(item)
            }
            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .lvFont(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, LVSpacing.xs)
        .animation(.snappy, value: item?.memoryId)
        .animation(.easeOut(duration: 0.2), value: confirmation)
        .sensoryFeedback(.impact(weight: .light), trigger: confirmation) { _, new in new != nil }
        .task(id: confirmation) {
            guard confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            onConfirmationShown()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("To revisit")
                .font(LVTypography.kicker.font)
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            if item != nil, remaining > 1 {
                Text("1 of \(remaining)")
                    .lvFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(remaining) memories to revisit")
            }
        }
    }

    private func memory(_ item: ResurfaceItemDTO) -> some View {
        Button {
            onOpen(item)
        } label: {
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(item.snippet)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label(item.why, systemImage: Self.symbol(for: item.reason))
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.memoryId)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.snippet). \(item.why)")
        .accessibilityHint("Opens the memory")
        .accessibilityAddTraits(.isButton)
    }

    private func actions(_ item: ResurfaceItemDTO) -> some View {
        HStack(spacing: LVSpacing.sm) {
            answer("Keep", action: .kept, item: item, label: "Keep this memory")
            answer("Soon", action: .soon, item: item, label: "Show it again in a few days")
            answer("Later", action: .later, item: item, label: "Show it again in about a month")
            Spacer(minLength: 0)
            Menu {
                Button("Never show again", systemImage: "eye.slash", role: .destructive) {
                    onAction(.never, item)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
        }
        .controlSize(.small)
        .disabled(isPending)
    }

    private func answer(
        _ title: String,
        action: MemoryReviewAction,
        item: ResurfaceItemDTO,
        label: String
    ) -> some View {
        Button {
            onAction(action, item)
        } label: {
            Text(title)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    static func symbol(for reason: ResurfaceReason) -> String {
        switch reason {
        case .due: "clock.arrow.circlepath"
        case .onThisDay: "calendar"
        case .fading: "hourglass"
        case .unknown: "sparkles"
        }
    }
}

#if DEBUG
#Preview {
    List {
        Section("Today") {
            ResurfaceCard(
                item: ResurfaceItemDTO(
                    memoryId: UUID(),
                    snippet: "Decided to keep the API flat — no nested resources until a second client needs them.",
                    kind: "decision",
                    createdAt: Date().addingTimeInterval(-86400 * 365),
                    reason: .onThisDay,
                    why: "Saved a year ago today"
                ),
                remaining: 3,
                confirmation: nil,
                isPending: false,
                errorMessage: nil,
                onOpen: { _ in },
                onAction: { _, _ in },
                onConfirmationShown: {}
            )
        }
    }
}
#endif
