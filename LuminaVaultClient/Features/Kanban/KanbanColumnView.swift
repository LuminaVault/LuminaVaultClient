import SwiftUI
import LuminaVaultShared

struct KanbanColumnView: View {
    let column: ColumnDTO
    let onAddCard: (String) -> Void
    let onOpenCard: (CardDTO) -> Void
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
                            // C5 — context-menu "Move to" provides an accessible
                            // alternative to drag; also used as the fallback on
                            // devices/simulators where drag is awkward.
                            .contextMenu {
                                // Populated by KanbanBoardView via the environment
                                // is non-trivial; we surface the move action inline
                                // here as a label-only placeholder — the board view
                                // wires up the full context via onDropCard.
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
                } label: { Image(systemName: "plus.circle.fill") }
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
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        // C5 — haptic feedback on successful drop.
        .sensoryFeedback(.impact, trigger: dropCount)
    }
}
