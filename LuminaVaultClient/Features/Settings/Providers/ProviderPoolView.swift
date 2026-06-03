// LuminaVaultClient/LuminaVaultClient/Features/Settings/Providers/ProviderPoolView.swift
//
// Phase 2 item 6 (layer 2) — manage a provider's round-robin credential
// pool: list / add / delete extra API keys. Requests rotate across the
// primary key + these to spread rate limits. Plaintext is never read back.

import LuminaVaultShared
import SwiftUI

struct ProviderPoolView: View {
    let client: ProvidersClientProtocol
    let provider: ProviderID

    @State private var keys: [ProviderPoolKeyDTO] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var newKey = ""
    @State private var newLabel = ""
    @State private var isWorking = false

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }

            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if keys.isEmpty {
                    Text("No pool keys yet — the primary key is used alone.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(keys, id: \.id) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.label?.isEmpty == false ? key.label! : "Key")
                            if let created = key.createdAt {
                                Text("Added \(created.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in Task { await delete(offsets) } }
                }
            } header: {
                Text("Pool keys")
            }

            Section {
                SecureField("API key", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Label (optional)", text: $newLabel)
                Button("Add key") { Task { await add() } }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            } header: {
                Text("Add a key")
            } footer: {
                Text("Requests round-robin across the primary key plus these to spread rate limits.")
            }
        }
        .navigationTitle("\(ProvidersPaneViewModel.displayName(for: provider)) pool")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            keys = try await client.listPool(provider).keys
        } catch {
            self.error = "Couldn't load the key pool."
        }
    }

    private func add() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        do {
            let created = try await client.addPool(
                provider,
                ProviderPoolAddRequest(apiKey: newKey, label: label.isEmpty ? nil : label)
            )
            keys.append(created)
            newKey = ""
            newLabel = ""
        } catch {
            self.error = "Couldn't add that key."
        }
    }

    private func delete(_ offsets: IndexSet) async {
        let targets = offsets.map { keys[$0] }
        for key in targets {
            do {
                try await client.deletePool(provider, keyID: key.id)
                keys.removeAll { $0.id == key.id }
            } catch {
                self.error = "Couldn't delete that key."
            }
        }
    }
}
