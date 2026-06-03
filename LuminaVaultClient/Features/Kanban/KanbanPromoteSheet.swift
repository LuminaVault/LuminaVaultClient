import SwiftUI
import LuminaVaultShared

/// Promote a card to a scheduled Job — recurring (cron) or one-time (run_at).
/// Collects the schedule, per-run instructions (defaulting to the card body),
/// and an optional domain hint, then calls `POST /v1/cards/:id/promote`. Each
/// run files its result into the vault (no board clutter).
struct KanbanPromoteSheet: View {
    let card: CardDTO
    let viewModel: KanbanBoardViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case recurring = "Recurring"
        case oneTime = "One-time"
        var id: String { rawValue }
    }

    /// (label, cron) presets — covers the common cadences without making the
    /// user hand-write cron. "Custom" reveals the raw field.
    private static let presets: [(String, String)] = [
        ("Every day at 9 AM", "0 9 * * *"),
        ("Every Monday at 9 AM", "0 9 * * 1"),
        ("Every hour", "0 * * * *"),
        ("Every weekday at 8 AM", "0 8 * * 1-5"),
    ]

    @State private var mode: Mode = .recurring
    @State private var cron: String = "0 9 * * *"
    @State private var isCustomCron = false
    @State private var runAt: Date = Date().addingTimeInterval(3600)
    @State private var prompt: String = ""
    @State private var domain: String = ""
    @State private var isPromoting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch mode {
                case .recurring:
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
                case .oneTime:
                    Section("When") {
                        DatePicker("Run at", selection: $runAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section(mode == .oneTime ? "What should it do?" : "What should it do each run?") {
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
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch mode {
        case .recurring:
            let c = cron.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c != "__custom__"
        case .oneTime:
            return runAt > Date()
        }
    }

    private func promote() async {
        isPromoting = true
        defer { isPromoting = false }
        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let domainArg = trimmedDomain.isEmpty ? nil : trimmedDomain
        let request: CardPromoteRequest
        switch mode {
        case .recurring:
            request = CardPromoteRequest(cron: cron, domain: domainArg, prompt: cleanPrompt)
        case .oneTime:
            request = CardPromoteRequest(runAt: runAt, domain: domainArg, prompt: cleanPrompt)
        }
        let job = await viewModel.promoteCard(card.id, request)
        if job != nil { dismiss() }
    }
}
