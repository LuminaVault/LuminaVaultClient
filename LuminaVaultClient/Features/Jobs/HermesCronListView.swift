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
}

struct HermesCronListView: View {
    @State private var viewModel: HermesCronListViewModel

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
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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
