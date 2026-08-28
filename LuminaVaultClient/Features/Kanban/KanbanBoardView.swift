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
            LazyHStack(alignment: .top, spacing: 14) {
                if let board = viewModel.board {
                    ForEach(board.columns) { column in
                        KanbanColumnView(
                            column: column,
                            // Sibling columns, so the card context menu can
                            // offer a "Move to" that doesn't require dragging.
                            otherColumns: board.columns.filter { $0.id != column.id },
                            onAddCard: { title in Task { await viewModel.addCard(columnID: column.id, title: title) } },
                            onOpenCard: { detailCard = $0 },
                            onMoveCard: { cardID, targetColumn in
                                Task { await viewModel.moveCard(cardID, toColumn: targetColumn, before: nil, after: nil) }
                            },
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
            .padding(.vertical)
            .scrollTargetLayout()
        }
        // Each column carries its own vertical `ScrollView`, a
        // `.dropDestination` and a per-card `.contextMenu`, so the horizontal
        // pan was competing with three recognizers on every drag. Snapping the
        // board to column boundaries settles the horizontal axis quickly and
        // stops it fighting the vertical one.
        .scrollTargetBehavior(.viewAligned)
        // Horizontal inset lives here rather than in the stack's padding, so
        // the first column snaps flush instead of resting 16pt off.
        .contentMargins(.horizontal, LVSpacing.base, for: .scrollContent)
        .background(Color.black.opacity(0.92).ignoresSafeArea())
        .navigationTitle(viewModel.board?.title ?? "Board")
        .task { await viewModel.load(); viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .sheet(item: $detailCard) { card in
            KanbanCardDetailSheet(card: card, viewModel: viewModel)
        }
    }
}
