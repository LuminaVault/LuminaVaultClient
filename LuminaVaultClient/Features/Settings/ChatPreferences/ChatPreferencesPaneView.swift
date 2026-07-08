// LuminaVaultClient/LuminaVaultClient/Features/Settings/ChatPreferences/ChatPreferencesPaneView.swift
import SwiftUI

struct ChatPreferencesPaneView: View {
    @State private var viewModel: ChatPreferencesPaneViewModel
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true

    init(client: any ChatExperienceClientProtocol) {
        _viewModel = State(initialValue: ChatPreferencesPaneViewModel(client: client))
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Auto-expand thinking",
                    isOn: Binding(
                        get: { viewModel.preferences.autoExpandThinking },
                        set: { value in Task { await viewModel.setAutoExpandThinking(value) } }
                    )
                )

                Toggle(
                    "Send on Return",
                    isOn: Binding(
                        get: { viewModel.preferences.sendOnReturn },
                        set: { value in Task { await viewModel.setSendOnReturn(value) } }
                    )
                )
            } header: {
                Text("Chat")
            } footer: {
                Text("These preferences sync across LuminaVault clients.")
            }

            Section {
                Toggle("Haptics", isOn: $hapticsEnabled)
            } header: {
                Text("This Device")
            } footer: {
                Text("Haptics stay local to this iPhone.")
            }

            if viewModel.isSaving {
                Section {
                    HStack {
                        Text("Saving")
                        Spacer()
                        ProgressView()
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task { await viewModel.load() }
    }
}
