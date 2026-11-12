// The tray's Open (and a double tap on a point). A port of the web app's
// `BrainNodeSheet.svelte`, same strings: a memory shows its body (loaded by
// `BrainNodeDetail` from its own vault); a note shows its title, vault and
// Space, which is all the graph knows.

import LuminaVaultShared
import SwiftUI

struct BrainNodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let detail: BrainNodeDetail
    let vaultName: String?
    let spaceName: String?
    /// The Memories screen edits the active vault only.
    let activeVaultID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let node = detail.node {
                    content(node)
                        .padding(.horizontal, LVSpacing.base + LVSpacing.xs)
                        .padding(.vertical, LVSpacing.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(palette.backgroundBase)
            .navigationTitle(detail.node?.kind == .memory ? "Memory" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Ids compare by value, so case never matters.
    private var elsewhere: Bool {
        guard let id = detail.node?.vaultID, let activeVaultID else { return false }
        return id != activeVaultID
    }

    private func content(_ node: BrainGraphNodeDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(node.label)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("brain.detail.title")
                if elsewhere {
                    Text("In \(vaultName ?? "another vault")")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            facts
            if node.kind == .memory, let memory = detail.memory {
                Divider()
                memoryBody(memory)
            }
        }
    }

    @ViewBuilder
    private var facts: some View {
        let showVault = vaultName != nil && !elsewhere
        if showVault || spaceName != nil {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                if showVault, let vaultName { fact("Vault", vaultName) }
                if let spaceName { fact("Space", spaceName) }
            }
        }
    }

    private func fact(_ term: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.md) {
            Text(term)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(minWidth: 56, alignment: .leading)
            Text(value)
                .foregroundStyle(palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func memoryBody(_ state: BrainNodeDetail.MemoryState) -> some View {
        switch state {
        case .loading:
            HStack(spacing: LVSpacing.sm) {
                ProgressView()
                Text("Loading memory…").foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case let .failed(message):
            Text(message).foregroundStyle(.red)
        case let .loaded(memory):
            VStack(alignment: .leading, spacing: LVSpacing.md) {
                Text(Self.markdown(memory.content))
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !memory.tags.isEmpty {
                    LVFlowLayout(spacing: LVSpacing.xs + LVSpacing.hairline) {
                        ForEach(memory.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, LVSpacing.sm)
                                .padding(.vertical, LVSpacing.xs)
                                .background(Capsule().fill(palette.primary.opacity(0.15)))
                                .foregroundStyle(palette.primary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tags: \(memory.tags.joined(separator: ", "))")
                }
                // Where it was captured; nothing when it carries no coordinate.
                MemoryMapCard(memory: memory)
                if let created = memory.createdAt {
                    Text("Saved \(created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                if elsewhere {
                    Text("Switch to \(vaultName ?? "its vault") to edit this memory.")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    /// Inline Markdown (bold, links, code); the text as it is if it does not parse.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
