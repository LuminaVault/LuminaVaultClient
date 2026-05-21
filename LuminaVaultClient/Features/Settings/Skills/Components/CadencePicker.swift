// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/Components/CadencePicker.swift
//
// HER-247 / HER-178 — preset cadence picker + custom-cron escape hatch.
// Selecting "Default" sends an empty schedule_override to the server,
// clearing the row. Custom cron is validated client-side with a basic
// 5-field regex; server is the source of truth.

import SwiftUI

struct CadencePreset: Identifiable, Hashable {
    let id: String
    let label: String
    let cron: String?

    static let all: [CadencePreset] = [
        CadencePreset(id: "default", label: "Manifest default", cron: nil),
        CadencePreset(id: "daily7", label: "Daily 7am", cron: "0 7 * * *"),
        CadencePreset(id: "daily8", label: "Daily 8am", cron: "0 8 * * *"),
        CadencePreset(id: "daily9", label: "Daily 9am", cron: "0 9 * * *"),
        CadencePreset(id: "sundayPM", label: "Weekly Sun 6pm", cron: "0 18 * * 0"),
    ]
}

struct CadencePicker: View {
    @Binding var scheduleOverride: String?
    var onCommit: (String) -> Void

    @State private var showingCustom = false
    @State private var customCron: String = ""
    @State private var customError: String?

    private static let cronRegex = #/^[^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+$/#

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(CadencePreset.all) { preset in
                Button {
                    scheduleOverride = preset.cron
                    onCommit(preset.cron ?? "")
                    showingCustom = false
                } label: {
                    HStack {
                        Text(preset.label)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.lvTextPrimary)
                        Spacer()
                        if isCurrent(preset) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.lvCyan)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            DisclosureGroup("Custom cron…", isExpanded: $showingCustom) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("0 7 * * *", text: $customCron)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.lvNavy.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if let customError {
                        Text(customError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Button("Apply") {
                        if customCron.firstMatch(of: Self.cronRegex) != nil {
                            scheduleOverride = customCron
                            customError = nil
                            onCommit(customCron)
                        } else {
                            customError = "Cron must have five space-separated fields."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.lvCyan)
                    .disabled(customCron.isEmpty)
                }
                .padding(.top, 4)
            }
            .tint(.lvTextSub)
        }
    }

    private func isCurrent(_ preset: CadencePreset) -> Bool {
        preset.cron == scheduleOverride
    }
}
