// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectionResultView.swift
//
// HER-194 — full-screen-ish modal that renders the skill's markdown
// (with HER-155 wikilink resolution), celebrates briefly on the mascot,
// and offers Save (cached upload, no second LLM call) and Share.

import LuminaVaultShared
import SwiftUI

struct ReflectionResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let skill: ReflectionSkill
    let topic: String?
    @Bindable var runner: ReflectionRunner
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    var onSaved: () -> Void = {}

    @State private var celebrate: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mascotHeader
                    title
                    contentBody
                }
                .padding(20)
            }
            .lvBackground()
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        runner.reset()
                        dismiss()
                    }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                celebrate = false
            }
        }
    }

    private var mascotHeader: some View {
        HermieMascotView(
            state: celebrate ? .celebrating : mascotState(for: runner.state),
            size: 96,
            fallbackImageName: "OnboardingMascot",
        )
        .frame(maxWidth: .infinity)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.title)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if let topic, !topic.isEmpty {
                Text(topic)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch runner.state {
        case .idle, .running:
            HStack { Spacer(); ProgressView().tint(palette.primary); Spacer() }
                .padding(.vertical, 40)

        case .result(let response), .saving(let response):
            WikilinkMarkdownView(
                markdown: response.markdown,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
            actionRow(for: response, isSaving: runner.state.isSaving)

        case .saved(let response, let savedPath):
            WikilinkMarkdownView(
                markdown: response.markdown,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
            savedConfirmation(savedPath: savedPath)
                .onAppear { onSaved() }

        case .failed(let error):
            errorBlock(error: error)
        }
    }

    private func actionRow(for response: SkillRunResponse, isSaving: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await runner.save(skill: skill, topic: topic, response: response) }
            } label: {
                Text(isSaving ? "Saving…" : "Save to Vault")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(palette.primary, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            ShareLink(item: response.markdown) {
                Text("Share")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func savedConfirmation(savedPath: String) -> some View {
        Label("Saved to \(savedPath)", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.glowPrimary)
            .padding(.top, 12)
    }

    private func errorBlock(error: ReflectionError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red.opacity(0.9))
            Button("Dismiss") {
                runner.reset()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 20)
    }

    private func mascotState(for state: ReflectionRunner.State) -> HermieMascotState {
        switch state {
        case .running, .saving: .thinking
        case .result, .saved: .happy
        case .failed, .idle: .idle
        }
    }
}

extension ReflectionRunner.State {
    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }
}
