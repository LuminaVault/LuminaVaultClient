import SwiftUI
import LuminaVaultShared

/// Promote a card to a scheduled Job. Collects a cron schedule, the per-run
/// instructions (defaulting to the card body), and an optional domain hint,
/// then calls `POST /v1/cards/:id/promote`. Each run files its result into the
/// vault (no board clutter).
struct KanbanPromoteSheet: View {
    let card: CardDTO
    let viewModel: KanbanBoardViewModel
    @Environment(\.dismiss) private var dismiss

    /// (label, cron) presets — covers the common cadences without making the
    /// user hand-write cron. "Custom" reveals the raw field.
    private static let presets: [(String, String)] = [
        ("Every day at 9 AM", "0 9 * * *"),
        ("Every Monday at 9 AM", "0 9 * * 1"),
        ("Every hour", "0 * * * *"),
        ("Every weekday at 8 AM", "0 8 * * 1-5"),
    ]

    @State private var cron: String = "0 9 * * *"
    @State private var isCustomCron = false
    @State private var prompt: String = ""
    @State private var domain: String = ""
    @State private var isPromoting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    Picker("Runs", selection: $cron) {
                        ForEach(Self.presets, id: \.1) { Text($0.0).tag($0.1) }
                        Text("Custom…").tag("__custom__")
                    }
                    .onChange(of: cron) { _, new in isCustomCron = (new == "__custom__") }
                    if isCustomCron {
                        TextField("Cron (e.g. 0 9 * * 1)", text: Binding(
                            get: { cron == "__custom__" ? "" : cron },
                            set: { cron = $0 },
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }
                Section("What should it do each run?") {
                    TextEditor(text: $prompt).frame(minHeight: 100)
                }
                Section("Domain (optional)") {
                    TextField("stocks, sports, ai, health…", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err = viewModel.lastError {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Promote to Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Promote") { Task { await promote() } }
                        .disabled(isPromoting || !isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { prompt = card.body ?? "" }
        }
    }

    private var isValid: Bool {
        let c = cron.trimmingCharacters(in: .whitespaces)
        return !c.isEmpty && c != "__custom__"
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func promote() async {
        isPromoting = true
        defer { isPromoting = false }
        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        let job = await viewModel.promoteCard(card.id, CardPromoteRequest(
            cron: cron,
            domain: trimmedDomain.isEmpty ? nil : trimmedDomain,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
        ))
        if job != nil { dismiss() }
    }
}
