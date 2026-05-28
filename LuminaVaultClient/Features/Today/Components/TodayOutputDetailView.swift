// LuminaVaultClient/LuminaVaultClient/Features/Today/Components/TodayOutputDetailView.swift
//
// HER-264 — destination sheet presented from `TodayCardView.onTap`.
// Renders the output's markdown body inline. Once memo / memory /
// vault file viewers expose a stable navigation API, the body will
// be replaced with a push into those surfaces; for now the inline
// reader covers daily-brief and weekly-memo cases verbatim.

import LuminaVaultShared
import SwiftUI

struct TodayOutputDetailView: View {

    @Environment(\.lvPalette) private var palette

    let output: SkillOutputDTO
    /// HER-155 follow-up — when both clients are present the body
    /// renders through `WikilinkMarkdownView` so `[[memory:uuid]]` and
    /// `[[note]]` citations in daily-brief / weekly-memo bodies are
    /// tappable. Optional so existing callers (and previews) compile
    /// without the new wiring.
    var vaultClient: (any VaultClientProtocol)?
    var memoryClient: (any MemoryClientProtocol)?
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(output.headline)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)

                    Text(output.skillName)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .textCase(.uppercase)

                    Divider().background(palette.surfaceStroke)

                    rendered
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    sourceFooter
                }
                .padding(20)
            }
            .lvBackground()
            .navigationTitle("Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingShare = true } label: {
                        LVIconView(.squareAndArrowUp)
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                TodayShareSheet(activityItems: shareItems)
            }
        }
    }

    @ViewBuilder
    private var sourceFooter: some View {
        if let memoryID = output.memoryID {
            sourceLabel("Memory", value: memoryID.uuidString)
        } else if let memoID = output.memoID {
            sourceLabel("Memo", value: memoID.uuidString)
        } else if let vaultFilePath = output.vaultFilePath {
            sourceLabel("Vault file", value: vaultFilePath)
        }
    }

    private func sourceLabel(_ kind: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().background(palette.surfaceStroke)
            Text("Source — \(kind)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    @ViewBuilder
    private var rendered: some View {
        if let vaultClient, let memoryClient {
            WikilinkMarkdownView(
                markdown: output.body,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
        } else if let attr = try? AttributedString(markdown: output.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
        } else {
            Text(output.body)
        }
    }

    /// HER-264 — share string carries the output headline + body + a
    /// `via Lumina` watermark (no asset dependency).
    private var shareItems: [Any] {
        let watermark = "\n\n— via Lumina"
        return ["\(output.headline)\n\n\(output.body)\(watermark)"]
    }
}

/// Thin UIViewControllerRepresentable wrapper around UIActivityViewController.
struct TodayShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
