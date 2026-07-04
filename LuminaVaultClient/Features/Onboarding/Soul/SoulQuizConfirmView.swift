// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizConfirmView.swift
//
// HER-100 step 5 — preview the server-composed SOUL.md (dry-run
// POST /v1/soul/compose), show the locked core covenant read-only,
// let the user hand-edit the rest inline, then save via PUT /v1/soul
// + PATCH /v1/onboarding. On success, clears persistence and hands
// control back to the container via the `onSaved` callback.

import LuminaVaultShared
import SwiftUI

struct SoulQuizConfirmView: View {
    @Bindable var state: SoulQuizState
    let soulClient: any SoulClientProtocol
    let onboardingClient: any OnboardingClientProtocol
    let onSaved: (OnboardingStateDTO) -> Void

    @Environment(\.lvPalette) private var palette

    /// Backing storage for the inline editor — the editable portion of the
    /// composed draft. Initialised from the dry-run compose the first time
    /// the view appears so each re-entry preserves the user's edits across
    /// back-navigation.
    @State private var draft: String = ""
    /// Front-matter/heading + locked core from the composed document; the
    /// editable draft is re-attached to these on save.
    @State private var parts: SoulDocumentParts?
    @State private var isComposing = false
    @State private var composeError: String?

    var body: some View {
        SoulQuizStepScaffold(
            number: 5,
            title: BrandCopy.soulConfirmTitle,
            subtitle: "Review the SOUL.md below. Tweak anything you want, then save."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if isComposing {
                    ProgressView("Composing your SOUL.md…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    if let core = parts?.core {
                        SoulLockedCoreCard(core: core)
                    }
                    TextEditor(text: $draft)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 280)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(palette.surfaceStroke, lineWidth: 1)
                        }
                        .disabled(state.isSaving)
                }
                if let error = composeError ?? state.saveError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            LVButton("Save SOUL.md", isLoading: state.isSaving) {
                Task { await save() }
            }
            .disabled(
                state.isSaving || isComposing
                    || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .task { await hydrateDraftIfNeeded() }
    }

    private func hydrateDraftIfNeeded() async {
        // Re-entry with prior edits: restore them and re-split around the core.
        if let saved = state.answers.editedMarkdown, !saved.isEmpty {
            let split = SoulCoreParser.parse(saved)
            parts = split
            draft = split.editable
            return
        }
        guard draft.isEmpty, !isComposing else { return }
        isComposing = true
        composeError = nil
        defer { isComposing = false }
        do {
            let response = try await soulClient.compose(
                SoulComposeRequest(from: state.answers, dryRun: true)
            )
            let split = SoulCoreParser.parse(response.markdown)
            parts = split
            draft = split.editable
        } catch {
            composeError = "Couldn't compose your SOUL.md — \(error.localizedDescription). Go back and retry, or edit from scratch below."
        }
    }

    private func save() async {
        state.beginSave()
        let body = if let parts {
            SoulCoreParser.assemble(parts, editable: draft)
        } else {
            draft
        }
        state.answers.editedMarkdown = body
        do {
            // The server strips + re-injects the canonical core on write, so
            // even a mangled document can't drop the covenant.
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

/// Read-only presentation of the server-managed core covenant. The lock is
/// cosmetic here — enforcement happens server-side on every write.
struct SoulLockedCoreCard: View {
    let core: String

    @Environment(\.lvPalette) private var palette
    @State private var isExpanded = false

    /// The covenant body without its HTML comment markers — cleaner to read.
    private var displayText: String {
        core
            .replacingOccurrences(
                of: "<!--[^>]*-->",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("Core covenant — managed by LuminaVault")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            if isExpanded {
                Text(displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.surfaceStroke.opacity(0.6), lineWidth: 1)
        }
    }
}
