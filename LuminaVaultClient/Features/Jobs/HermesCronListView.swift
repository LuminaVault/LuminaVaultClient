// LuminaVaultClient/LuminaVaultClient/Features/Jobs/HermesCronListView.swift
//
// TUI-parity: list the connected Hermes's cron jobs (managed or BYO — the server
// picks the transport). Read-only for now; create-from-chat lands next.

import Observation
import SwiftUI

@MainActor
@Observable
final class HermesCronListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    var source: String = ""
    var jobs: [HermesCronJobDTO] = []

    private let client: HermesCronClientProtocol

    init(client: HermesCronClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.list()
            source = response.source
            jobs = response.jobs
            state = .loaded
        } catch let APIError.httpError(status, _) where status == 404 {
            state = .failed("No Hermes is connected for this account, or it exposes no cron API.")
        } catch {
            state = .failed("Couldn't load Hermes cron jobs.")
        }
    }

    // MARK: - Create from chat

    var createText = ""
    var previewedSpec: CronSpecDTO?
    var createBusy = false
    var createError: String?

    func preview() async {
        let text = createText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        createBusy = true; createError = nil; previewedSpec = nil
        defer { createBusy = false }
        do { previewedSpec = try await client.preview(text: text) }
        catch {
            createError = "Couldn't turn that into a schedule. Try e.g. \"every weekday 9am, AI news digest to Telegram\"."
        }
    }

    /// Returns true on success (caller dismisses the sheet).
    func create() async -> Bool {
        guard let spec = previewedSpec else { return false }
        createBusy = true; createError = nil
        defer { createBusy = false }
        do {
            let response = try await client.create(spec: spec)
            source = response.source
            jobs = response.jobs
            previewedSpec = nil
            createText = ""
            return true
        } catch {
            createError = "Couldn't create the job."
            return false
        }
    }
}

struct HermesCronListView: View {
    @State private var viewModel: HermesCronListViewModel
    @State private var showCreate = false

    init(client: HermesCronClientProtocol) {
        _viewModel = State(initialValue: HermesCronListViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { HStack(spacing: 12) { ProgressView(); Text("Loading…") } }
            case let .failed(message):
                Section { Text(message).foregroundStyle(.secondary).font(.footnote) }
            case .loaded:
                if viewModel.jobs.isEmpty {
                    Section { Text("No scheduled jobs.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        ForEach(viewModel.jobs) { job in
                            row(job)
                        }
                    } header: {
                        Text("\(viewModel.jobs.count) job\(viewModel.jobs.count == 1 ? "" : "s") · \(viewModel.source.uppercased())")
                    } footer: {
                        Text("Scheduled tasks running on your Hermes. Create-from-chat is coming next.")
                    }
                }
            }
        }
        .navigationTitle("Hermes Cron")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) { createSheet }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Describe a job — e.g. \"every weekday 9am, AI news digest to Telegram\"",
                        text: $viewModel.createText,
                        axis: .vertical,
                    )
                    .lineLimit(2 ... 5)
                    Button("Preview") { Task { await viewModel.preview() } }
                        .disabled(viewModel.createBusy || viewModel.createText.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Plain English → a scheduled Hermes job. You confirm before it's created.")
                }

                if let spec = viewModel.previewedSpec {
                    Section("Will create") {
                        LabeledContent("Schedule", value: spec.schedule)
                        if let name = spec.name, !name.isEmpty { LabeledContent("Name", value: name) }
                        if let deliver = spec.deliver, !deliver.isEmpty { LabeledContent("Deliver", value: deliver) }
                        if let prompt = spec.prompt, !prompt.isEmpty {
                            Text(prompt).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button("Create job") {
                            Task { if await viewModel.create() { showCreate = false } }
                        }
                        .disabled(viewModel.createBusy)
                    }
                }

                if let error = viewModel.createError {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("New Hermes Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreate = false }
                }
            }
        }
    }

    private func row(_ job: HermesCronJobDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.name ?? job.id).fontWeight(.medium).lineLimit(1)
                Spacer()
                if let status = job.status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(status == "active" ? .green : .secondary)
                }
            }
            HStack(spacing: 8) {
                if let schedule = job.schedule {
                    Label(schedule, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
                if let deliver = job.deliver, !deliver.isEmpty {
                    Label(deliver, systemImage: "paperplane").font(.caption).foregroundStyle(.secondary)
                }
                if job.mode == "script" {
                    Label("script", systemImage: "terminal").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let lastRun = job.lastRun {
                Text("Last run: \(lastRun)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
