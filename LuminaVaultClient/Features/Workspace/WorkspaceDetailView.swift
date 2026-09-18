// LuminaVaultClient/LuminaVaultClient/Features/Workspace/WorkspaceDetailView.swift
//
// One file or one diff, full screen.
//
// A diff is coloured by line prefix rather than parsed into hunks, matching
// the server sending a patch as text: parsing would mean inventing a hunk
// model every consumer then has to agree with, and this is what a reader
// actually needs.

import LuminaVaultShared
import SwiftUI

struct WorkspaceDetailView: View {
    enum Target: Equatable {
        case file(path: String)
        case diff(path: String)

        var title: String {
            switch self {
            case let .file(path), let .diff(path):
                String(path.split(separator: "/").last ?? "")
            }
        }
    }

    let viewModel: WorkspaceViewModel
    let target: Target

    @Environment(\.lvPalette) private var palette

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.diffTruncated, case .diff = target {
                    // Saying so beats presenting a cut-short patch as the
                    // whole change.
                    Text("This diff was too large to show in full.")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.bottom, LVSpacing.sm)
                }

                switch target {
                case .diff:
                    if let diff = viewModel.diffText {
                        ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            Text(String(line))
                                .font(.caption2.monospaced())
                                .foregroundStyle(tone(for: String(line)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .file:
                    if let content = viewModel.fileContent {
                        Text(content)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(LVSpacing.md)
        }
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            switch target {
            case let .file(path): await viewModel.showFile(path: path)
            case let .diff(path): await viewModel.showDiff(file: path)
            }
        }
    }

    private func tone(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return palette.textSecondary }
        if line.hasPrefix("@@") { return palette.accent }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return palette.textPrimary
    }
}
