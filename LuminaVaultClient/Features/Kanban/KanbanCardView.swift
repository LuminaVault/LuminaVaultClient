import SwiftUI
import LuminaVaultShared

struct KanbanCardView: View {
    let card: CardDTO
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let p = card.priority { priorityDot(p) }
                Text(card.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if let body = card.body, !body.isEmpty {
                Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let due = card.dueAt {
                Text(due, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(due < .now ? .red : .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        // C5 — make every card a drag source. The payload is the UUID string;
        // the receiving column's .dropDestination parses it back to UUID.
        .draggable(card.id.uuidString)
    }
    private func priorityDot(_ p: CardPriority) -> some View {
        Circle().fill(p == .urgent || p == .high ? Color.yellow : Color.cyan).frame(width: 8, height: 8)
    }
}
