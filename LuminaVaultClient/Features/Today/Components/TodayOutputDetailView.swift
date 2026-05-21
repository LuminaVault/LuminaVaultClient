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
    let output: SkillOutputDTO
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(output.headline)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.lvTextPrimary)

                    Text(output.skillName)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.lvTextSub)
                        .textCase(.uppercase)

                    Divider().background(Color.lvBorder)

                    rendered
                        .font(.system(size: 14))
                        .foregroundStyle(Color.lvTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !output.sourceMemoryIDs.isEmpty {
                        Divider().background(Color.lvBorder)
                        Text("Cited memories")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.lvTextSub)
                            .textCase(.uppercase)
                        ForEach(output.sourceMemoryIDs.prefix(10), id: \.self) { id in
                            Text(id.uuidString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.lvTextMuted)
                        }
                    }
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
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(activityItems: shareItems)
            }
        }
    }

    @ViewBuilder
    private var rendered: some View {
        if let attr = try? AttributedString(markdown: output.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
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
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
