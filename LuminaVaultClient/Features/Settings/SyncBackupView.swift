// LuminaVaultClient/LuminaVaultClient/Features/Settings/SyncBackupView.swift
import SwiftData
import SwiftUI

/// HER-39 — surfaces the offline sync engine to the user. Lives under
/// Settings → Sync & Backup. Shows the live state (mirrored from
/// `AppState.syncState`), a manual "Sync now" button, and the rolling
/// activity log from `SyncLogEntry`.
struct SyncBackupView: View {
    @Environment(AppState.self) private var appState
    @Query private var logEntries: [SyncLogEntry]
    @State private var isManualSyncing = false

    init() {
        let predicate = #Predicate<SyncLogEntry> { _ in true }
        _logEntries = Query(
            filter: predicate,
            sort: \SyncLogEntry.timestamp,
            order: .reverse
        )
    }

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    // HER-291: kept as Image — runtime symbol name
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateColor)
                    Text(stateText)
                        .font(.body)
                }
                Button {
                    Task { await runManualSync() }
                } label: {
                    Label(isManualSyncing ? "Syncing…" : "Sync now",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isManualSyncing)
            }

            Section("Recent activity") {
                if logEntries.isEmpty {
                    Text("No sync activity yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logEntries.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.result.capitalized)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(resultColor(for: entry.result))
                                Spacer()
                                Text(entry.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let message = entry.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sync & Backup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runManualSync() async {
        guard let tenantID = appState.currentUserId, !isManualSyncing else { return }
        isManualSyncing = true
        defer { isManualSyncing = false }
        await appState.syncManager.runUntilDrained(tenantID: tenantID)
    }

    // MARK: - Status helpers

    private var stateText: String {
        switch appState.syncState {
        case .idle: "Up to date."
        case let .syncing(pending): pending > 0 ? "Syncing \(pending) pending…" : "Syncing…"
        case .offline: "Offline — waiting for reachability."
        case let .error(message): "Last error: \(message)"
        }
    }

    private var stateIcon: String {
        switch appState.syncState {
        case .idle: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch appState.syncState {
        case .idle: .green
        case .syncing: .blue
        case .offline: .orange
        case .error: .red
        }
    }

    private func resultColor(for result: String) -> Color {
        switch result {
        case "success": .green
        case "poisoned": .red
        case "failure": .orange
        default: .secondary
        }
    }
}
