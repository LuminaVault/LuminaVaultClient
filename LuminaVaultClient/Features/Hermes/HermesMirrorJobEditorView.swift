// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesMirrorJobEditorView.swift
//
// Hermes Companion Phase 2 — create or edit a cron job on the user's Hermes.
//
// Schedule and deliver are free-form because Hermes' grammars are richer than
// a picker: `every 2h`, a cron expression or a one-shot time; `origin`,
// `local`, `all` or `platform:chat_id:thread`, comma-separated. The field
// help says so rather than the UI quietly narrowing what the machine accepts.

import LuminaVaultShared
import SwiftUI

struct HermesMirrorJobEditorView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State var vm: HermesMirrorJobEditorViewModel
    /// Handed the saved job so the screen behind can adopt it without a
    /// round trip.
    let onSaved: (HermesMirroredJobDTO) -> Void

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    field(
                        "NAME",
                        text: $vm.name,
                        placeholder: "morning-brief",
                        help: vm.isEditing ? "Leave blank to keep the current name." : nil
                    )
                    field(
                        "SCHEDULE",
                        text: $vm.schedule,
                        placeholder: "every 2h",
                        help: "A cron expression, an interval like \"every 2h\", or a one-shot time."
                    )
                    multilineField(
                        "PROMPT",
                        text: $vm.prompt,
                        help: "What Hermes should do each time it runs."
                    )
                    field(
                        "DELIVER",
                        text: $vm.deliver,
                        placeholder: "origin",
                        help: "Where the result goes: origin, local, all, or platform:chat_id. Comma-separated. Blank leaves it unchanged."
                    )
                    field(
                        "SKILLS",
                        text: $vm.skills,
                        placeholder: "research, summarise",
                        help: "Comma-separated skill names. Blank leaves them unchanged."
                    )

                    if let failure = vm.failure {
                        VStack(alignment: .leading, spacing: LVSpacing.xs) {
                            Text(failure.message)
                                .lvFont(.callout)
                                .foregroundStyle(.red)
                            if let guidance = failure.guidance {
                                Text(guidance)
                                    .lvFont(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
                .padding(LVSpacing.lg)
            }
        }
        .navigationTitle(vm.isEditing ? "Edit job" : "New job")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await vm.save()
                        if let saved = vm.saved {
                            onSaved(saved)
                            dismiss()
                        }
                    }
                }
                .disabled(!vm.canSave)
            }
        }
        .overlay {
            if vm.isSaving {
                ProgressView().tint(palette.primary)
            }
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        help: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(label)
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .padding(LVSpacing.sm)
                .background(inputBackground)
            if let help {
                Text(help)
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
    }

    private func multilineField(
        _ label: String,
        text: Binding<String>,
        help: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(label)
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            TextEditor(text: text)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(LVSpacing.sm)
                .background(inputBackground)
            if let help {
                Text(help)
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
            .fill(palette.surface.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
    }
}
