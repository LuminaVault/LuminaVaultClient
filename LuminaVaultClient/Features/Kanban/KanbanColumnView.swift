import SwiftUI
import LuminaVaultShared

struct KanbanColumnView: View {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(column.title.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(.cyan)
            ScrollView {
                LazyVStack(spacing: 10) {
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
            HStack {
                TextField("New card", text: $newCardTitle).textFieldStyle(.roundedBorder)
                Button {
                    let t = newCardTitle.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    onAddCard(t); newCardTitle = ""
                } label: { LVIconView(.plusCircleFill, size: 22, label: "Add card") }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        // C5 — highlight with cyan border while a card is dragged over.
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isDropTargeted ? Color.cyan : Color.clear, lineWidth: 2)
        )
        .lvAnimation(LVMotion.quick, value: isDropTargeted)
        // C5 — haptic feedback on successful drop.
        .sensoryFeedback(.impact, trigger: dropCount)
    }
}
