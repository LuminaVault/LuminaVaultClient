// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatArtifactStrip.swift
//
// What the agent produced this turn, as chips under the transcript.
//
// Tap only. A tool producing a file offers a preview; it never opens the pane
// on the reader's behalf — see `ChatPreviewStore`.
//
// Artifacts key on Hermes session, not conversation, so this is empty until a
// turn escalates to a run. That is correct: a conversation that never ran an
// agent produced no artifacts.

import SwiftUI

struct ChatArtifactStrip: View {
    @Environment(\.lvPalette) private var palette

    let sessionID: String?
    let client: (any HermesArtifactsClientProtocol)?
    let store: ChatPreviewStore
    /// Bumped when a run finishes, so the strip re-reads what it produced.
    let refreshKey: Int

    @State private var artifacts: [HermesArtifactDTO] = []

    var body: some View {
        Group {
            if !artifacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LVSpacing.sm) {
                        ForEach(artifacts) { artifact in
                            Button {
                                store.open(.artifact(id: artifact.id.uuidString))
                            } label: {
                                Label(artifact.label, systemImage: icon(for: artifact.kind))
                                    .lvFont(.microTag)
                                    .lineLimit(1)
                                    .padding(.horizontal, LVSpacing.sm)
                                    .padding(.vertical, LVSpacing.xs)
                                    .overlay(Capsule().strokeBorder(palette.surfaceStroke))
                                    .frame(minHeight: 44)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.textPrimary)
                            .accessibilityHint("Opens a preview")
                        }
                    }
                }
                .accessibilityLabel("Artifacts from this turn")
            }
        }
        .task(id: "\(sessionID ?? "")#\(refreshKey)") {
            await load()
        }
    }

    private func load() async {
        guard let sessionID, !sessionID.isEmpty, let client else {
            artifacts = []
            return
        }
        do {
            let response = try await client.list(sessionID: sessionID, limit: 12)
            guard !Task.isCancelled else { return }
            artifacts = response.artifacts
            for artifact in response.artifacts {
                store.registerCandidate(.artifact(id: artifact.id.uuidString))
            }
        } catch {
            // A missing strip is a small loss next to an error banner over a
            // conversation that otherwise worked.
            if !Task.isCancelled { artifacts = [] }
        }
    }

    private func icon(for kind: HermesArtifactKind) -> String {
        switch kind {
        case .image: "photo"
        case .link: "link"
        case .file: "doc.text"
        }
    }
}
