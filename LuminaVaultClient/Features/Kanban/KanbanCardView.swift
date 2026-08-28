import SwiftUI
import LuminaVaultShared

struct KanbanCardView: View {
    @Environment(\.lvPalette) private var palette

    let card: CardDTO

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                if let priority = card.priority { priorityDot(priority) }
                Text(card.title)
                    .font(LVTypography.fieldLabel.font)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
            }
            if let body = card.body, !body.isEmpty {
                Text(body)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            if let due = card.dueAt {
                Text(due, format: .dateTime.month().day())
                    .font(LVTypography.microTag.font)
                    // `.red` is the system semantic red and adapts; the
                    // not-overdue case moves off `.secondary` so it tracks the
                    // theme like every other muted line on the board.
                    .foregroundStyle(due < .now ? Color.red : palette.textSecondary)
            }
        }
        .padding(LVSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element per card, so VoiceOver reads "High priority, Ship the
        // beta, …" as a card rather than four unrelated fragments — and so
        // the priority dot's label is actually spoken.
        .accessibilityElement(children: .combine)
        // Deliberately *not* another `.ultraThinMaterial`: these cards sit
        // inside a glass column, and stacking two translucent surfaces
        // collapses legibility. A flat `palette.surface` fill with the
        // palette's own hairline reads as a tile on the glass, has a real
        // Light variant — the old border was 8%-alpha white, invisible on a
        // light background, which SwiftLint's `near_invisible_opacity` rule
        // already flagged — and skips a per-card blur pass in a `LazyVStack`
        // that scrolls.
        .background(palette.surface, in: RoundedRectangle(cornerRadius: LVRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.lg, style: .continuous)
                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
        )
        // C5 — make every card a drag source. The payload is the UUID string;
        // the receiving column's .dropDestination parses it back to UUID.
        .draggable(card.id.uuidString)
    }

    /// Priority is otherwise carried by hue alone, which neither VoiceOver nor
    /// a colour-blind user can read, so the dot names itself.
    private func priorityDot(_ priority: CardPriority) -> some View {
        let isElevated = priority == .urgent || priority == .high
        return Circle()
            .fill(isElevated ? palette.accent : palette.primary)
            .frame(width: LVSpacing.sm, height: LVSpacing.sm)
            .accessibilityElement()
            .accessibilityLabel("\(priority.rawValue.capitalized) priority")
    }
}
