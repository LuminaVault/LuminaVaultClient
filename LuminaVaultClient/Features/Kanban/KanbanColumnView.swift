import SwiftUI
import LuminaVaultShared

struct KanbanColumnView: View {
    let column: ColumnDTO
    let onAddCard: (String) -> Void
    let onOpenCard: (CardDTO) -> Void
    @State private var newCardTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(column.title.uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(.cyan)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(column.cards) { card in
                        KanbanCardView(card: card).onTapGesture { onOpenCard(card) }
                    }
                }
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
    }
}
