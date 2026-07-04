// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizConfirmView.swift
//
// HER-100 step 5 — render the generated SOUL.md, let the user hand-
// edit it inline, then save via PUT /v1/soul + PATCH /v1/onboarding.
// On success, clears persistence and hands control back to the
// container via the `onSaved` callback.

import SwiftUI
import LuminaVaultShared

struct SoulQuizConfirmView: View {
    @Bindable var state: SoulQuizState
    let soulClient: any SoulClientProtocol
    let onboardingClient: any OnboardingClientProtocol
    let onSaved: (OnboardingStateDTO) -> Void

    @Environment(\.lvPalette) private var palette

    /// Backing storage for the inline editor — initialised from the
    /// generator the first time the view appears so each re-entry
    /// preserves the user's edits across back-navigation.
    @State private var draft: String = ""

    var body: some View {
        SoulQuizStepScaffold(
            number: 5,
            title: BrandCopy.soulConfirmTitle,
            subtitle: "Review the SOUL.md below. Tweak anything you want, then save."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $draft)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(palette.surfaceStroke, lineWidth: 1)
                    }
                    .disabled(state.isSaving)
                if let error = state.saveError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            LVButton("Save SOUL.md", isLoading: state.isSaving) {
                Task { await save() }
            }
            .disabled(state.isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { hydrateDraftIfNeeded() }
    }

    private func hydrateDraftIfNeeded() {
        if let saved = state.answers.editedMarkdown, !saved.isEmpty {
            draft = saved
        } else if draft.isEmpty {
            draft = SoulMdGenerator.render(state.answers)
        }
    }

    private func save() async {
        state.beginSave()
        let body = draft
        state.answers.editedMarkdown = body
        do {
            _ = try await soulClient.put(SoulPutRequest(markdown: body))
            let updated = try await onboardingClient.patch(
                OnboardingPatchRequest(soulConfiguredCompleted: true)
            )
            state.clearPersistence()
            state.endSave(error: nil)
            onSaved(updated)
        } catch {
            state.endSave(error: "Couldn't save — \(error.localizedDescription). Tap to retry.")
        }
    }
}
