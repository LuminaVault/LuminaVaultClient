import SwiftUI
import LuminaVaultShared

struct KanbanColumnView: View {
    @Environment(\.lvPalette) private var palette

    let column: ColumnDTO
    /// Every other column on the board, for the card context menu's
    /// "Move to" submenu.
    let otherColumns: [ColumnDTO]
    let onAddCard: (String) -> Void
    let onOpenCard: (CardDTO) -> Void
    /// Moves a card to another column without dragging.
    let onMoveCard: (UUID, UUID) -> Void
    // C5 — called when a card UUID is dropped onto this column.
    let onDropCard: (UUID) -> Void
    @State private var newCardTitle = ""
    // C5 — tracks whether a drag is currently over this column so we can
    // highlight the border.
    @State private var isDropTargeted = false
    // C5 — increments on each successful drop; drives .sensoryFeedback.
    @State private var dropCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            // Was `.foregroundStyle(.cyan)` — a fixed sRGB cyan that ignored
            // both the Light palette and the three non-cyan themes. The
            // uppercase column name is exactly the eyebrow `LVKickerLabel`
            // exists for, so it inherits `palette.primary` and the shared
            // kicker type/kerning instead of a second hand-rolled one.
            LVKickerLabel(column.title)
            ScrollView {
                LazyVStack(spacing: LVSpacing.md) {
                    ForEach(column.cards) { card in
                        KanbanCardView(card: card)
                            .onTapGesture { onOpenCard(card) }
                            // C5 — "Move to" is the non-drag path to the same
                            // outcome as `.dropDestination`. It used to be an
                            // *empty* `.contextMenu { }`, which still installed
                            // a long-press recognizer competing with the card's
                            // `.draggable` and presented nothing. Dragging is
                            // also unavailable to VoiceOver users, so this is
                            // the only route they have.
                            .contextMenu {
                                if otherColumns.isEmpty {
                                    Text("No other columns")
                                } else {
                                    ForEach(otherColumns) { target in
                                        Button("Move to \(target.title)") {
                                            onMoveCard(card.id, target.id)
                                        }
                                    }
                                }
                            }
                    }
                }
            }
            // C5 — the entire column card area (ScrollView + LazyVStack) is a
            // drop destination. MVP semantics: appends to end of the column.
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let cardID = UUID(uuidString: idString) else { return false }
                // Skip no-op drops (card dropped onto its own column).
                guard !column.cards.contains(where: { $0.id == cardID }) else { return false }
                onDropCard(cardID)
                dropCount += 1
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            HStack(spacing: LVSpacing.sm) {
                // `LVTextField`, not `.textFieldStyle(.roundedBorder)`. The
                // system style paints an opaque field: white in Light, *black*
                // in Dark — which on the glass column read as a hard black slab
                // with grey-on-black placeholder text. `LVTextField` is the
                // app's own field: `Color.lvGlass` fill, `palette.surfaceStroke`
                // edge, `palette.glowPrimary` focus ring, all adaptive.
                LVTextField(placeholder: "New card", text: $newCardTitle)
                    .submitLabel(.done)
                    .onSubmit(addCard)
                Button(action: addCard) {
                    LVIconView(.plusCircleFill, size: LVSize.tabBarGlyph, tint: palette.primary, label: "Add card")
                }
                .disabled(trimmedNewCardTitle.isEmpty)
            }
        }
        .padding(LVSpacing.md)
        .frame(width: Self.columnWidth)
        // `lvGlassCard` is the app's card surface: material + `palette.surface`
        // fill + `palette.surfaceStroke` edge, all of which have a Light
        // variant. A bare `.ultraThinMaterial` had no fill and no edge, so in
        // Light mode the column dissolved into the page.
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.5)
        // C5 — highlight the drop target while a card is dragged over.
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                .strokeBorder(isDropTargeted ? palette.primary : Color.clear, lineWidth: 2)
        )
        .lvAnimation(LVMotion.quick, value: isDropTargeted)
        // C5 — haptic feedback on successful drop.
        .sensoryFeedback(.impact, trigger: dropCount)
    }

    /// Board columns are a fixed width so `.scrollTargetBehavior(.viewAligned)`
    /// on the board has a stable snap stride.
    private static let columnWidth: CGFloat = 300

    private var trimmedNewCardTitle: String {
        newCardTitle.trimmingCharacters(in: .whitespaces)
    }

    private func addCard() {
        let title = trimmedNewCardTitle
        guard !title.isEmpty else { return }
        onAddCard(title)
        newCardTitle = ""
    }
}
