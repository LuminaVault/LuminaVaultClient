// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/AIDataConsentView.swift
//
// App Review guideline 5.1.2(i): before personal data goes to a third-party
// AI service, the app must say what is sent, to whom, and get the user's
// permission. This is the first post-auth step, ahead of vault creation, so
// nothing reaches a provider before the user agrees.
//
// The provider list mirrors the hosted service's routing (Anthropic for the
// free lane and background jobs, OpenRouter via Hermes for chat, then the
// fallbacks whose keys production holds) and the Privacy Policy at
// luminavault.fyi/privacy. Change all three together. Bump
// `AIDataConsent.currentVersion` when the list changes, so every user is asked
// again.
//
// Declining signs out: every core feature (answers, compile, capture
// enrichment) sends vault excerpts to a model, so there is no AI-free mode.

import SwiftUI

enum AIDataConsent {
    /// Version of the disclosure the user accepted. 0 = never asked.
    static let currentVersion = 1
    static let storageKey = "aiDataConsentVersion"

    static let primaryProviders = "Anthropic (Claude) or, for chat, models reached through OpenRouter"
    static let fallbackProviders = [
        "Google Gemini", "OpenAI", "xAI", "Groq",
        "Together AI", "Fireworks AI", "DeepInfra", "DeepSeek",
    ]
    static let imageProvider = "Cohere"
}

struct AIDataConsentView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("LuminaVault answers from your notes with the help of AI models run by other companies. Before anything is sent, here is what goes where.")
                        .font(.body)

                    section(
                        "What is sent",
                        "The parts of your vault a request needs: excerpts of notes, links and transcripts you saved, your question, and your SOUL.md. Photos and files you capture can be sent so they become searchable."
                    )
                    section(
                        "Who receives it",
                        "Depending on the feature, \(AIDataConsent.primaryProviders). If those are unavailable, a request can go to one of: \(AIDataConsent.fallbackProviders.joined(separator: ", ")). Image search uses \(AIDataConsent.imageProvider). If you add your own API key in Settings, requests go to that provider instead."
                    )
                    section(
                        "What it is used for",
                        "Only to answer you, organise your vault and run the jobs you set up. We do not sell your data or use your vault to train models. Each provider's own terms apply to what it receives."
                    )

                    Button("Read the Privacy Policy") { openURL(Config.privacyPolicyURL) }
                        .font(.subheadline)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(action: onAccept) {
                        Text("Allow and continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lvProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("aiConsent.accept")

                    Button("Don't allow and sign out", role: .destructive, action: onDecline)
                        .accessibilityIdentifier("aiConsent.decline")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Your data and AI")
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.body).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AIDataConsentView(onAccept: {}, onDecline: {})
}
