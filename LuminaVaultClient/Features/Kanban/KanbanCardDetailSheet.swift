import SwiftUI
import LuminaVaultShared

struct KanbanCardDetailSheet: View {
    let card: CardDTO
    let viewModel: KanbanBoardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var priority: CardPriority?
    @State private var dueAt: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Title", text: $title) }
                Section("Notes") { TextEditor(text: $bodyText).frame(minHeight: 120) }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(CardPriority?.none)
                        ForEach(CardPriority.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(CardPriority?.some(p))
                        }
                    }
                }
                Section("Due") {
                    Toggle("Has due date", isOn: Binding(get: { dueAt != nil }, set: { dueAt = $0 ? (dueAt ?? .now) : nil }))
                    if dueAt != nil {
                        DatePicker("Due", selection: Binding(get: { dueAt ?? .now }, set: { dueAt = $0 }), displayedComponents: .date)
                    }
                }
                Section {
                    Button("Delete", role: .destructive) { Task { await viewModel.deleteCard(card.id); dismiss() } }
                }
            }
            .navigationTitle("Card")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.editCard(card.id, .init(title: title, body: bodyText, priority: priority, dueAt: dueAt))
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { title = card.title; bodyText = card.body ?? ""; priority = card.priority; dueAt = card.dueAt }
        }
    }
}
