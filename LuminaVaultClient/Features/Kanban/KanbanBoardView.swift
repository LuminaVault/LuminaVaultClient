import SwiftUI
import LuminaVaultShared

struct KanbanBoardView: View {
    @State private var viewModel: KanbanBoardViewModel
    @State private var detailCard: CardDTO?

    init(boardID: UUID, client: any KanbanClientProtocol) {
        _viewModel = State(initialValue: KanbanBoardViewModel(boardID: boardID, client: client))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                if let board = viewModel.board {
                    ForEach(board.columns) { column in
                        KanbanColumnView(
                            column: column,
                            onAddCard: { title in Task { await viewModel.addCard(columnID: column.id, title: title) } },
                            onOpenCard: { detailCard = $0 },
                            // C5 — drop closure: append dragged card to this column
                            // (before = current last card so it goes to end, after = nil).
                            onDropCard: { cardID in
                                Task {
                                    await viewModel.moveCard(
                                        cardID,
                                        toColumn: column.id,
                                        before: column.cards.last?.id,
                                        after: nil
                                    )
                                }
                            }
                        )
                    }
                    Button { Task { await viewModel.addColumn(title: "New Column") } } label: {
                        Label("Add column", systemImage: "plus").padding()
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.92).ignoresSafeArea())
        .navigationTitle(viewModel.board?.title ?? "Board")
        .task { await viewModel.load(); viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .sheet(item: $detailCard) { card in
            KanbanCardDetailSheet(card: card, viewModel: viewModel)
        }
    }
}
