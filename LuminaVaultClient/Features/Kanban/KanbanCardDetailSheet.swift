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
    @State private var showPromote = false

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
                Section("Job") {
                    if let job = card.jobConfig, let slug = job.jobSlug {
                        LabeledContent("Scheduled job", value: slug)
                        if let cron = job.cron {
                            LabeledContent("Schedule", value: cron)
                        }
                    } else {
                        Button {
                            showPromote = true
                        } label: {
                            Label("Promote to Job", systemImage: "clock.arrow.2.circlepath")
                        }
                    }
                }
                Section {
                    Button("Delete", role: .destructive) { Task { await viewModel.deleteCard(card.id); dismiss() } }
                }
            }
            .navigationTitle("Card")
            .sheet(isPresented: $showPromote) {
                KanbanPromoteSheet(card: card, viewModel: viewModel)
            }
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
