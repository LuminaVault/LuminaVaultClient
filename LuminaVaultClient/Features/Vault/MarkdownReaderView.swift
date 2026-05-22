// LuminaVaultClient/LuminaVaultClient/Features/Vault/MarkdownReaderView.swift
// HER-105: in-app reader for a single vault file. Markdown gets rendered
// via SwiftUI's `AttributedString(markdown:)` for now — fast and
// dependency-free. Binary files fall through to a placeholder.
import SwiftUI

struct MarkdownReaderView: View {

    @Environment(\.lvPalette) private var palette

    let file: VaultFileDTO
    let vaultClient: VaultClientProtocol

    @State private var content: AttributedString?
    @State private var rawText: String?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text((file.path as NSString).lastPathComponent)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(file.path)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)

                Divider()
                    .background(palette.surfaceStroke)

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxWidth: .infinity)
                } else if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                } else if let content {
                    Text(content)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if let rawText {
                    Text(rawText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text("Binary file — preview unavailable.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .lvBackground()
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let (data, contentType) = try await vaultClient.readFile(relativePath: file.path)
            let isText = contentType.hasPrefix("text/")
                || contentType.contains("markdown")
                || contentType == "application/json"
            guard isText else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            self.rawText = text
            if contentType.contains("markdown") || file.path.hasSuffix(".md") {
                if let attributed = try? AttributedString(
                    markdown: text,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    ),
                ) {
                    self.content = attributed
                }
            }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
