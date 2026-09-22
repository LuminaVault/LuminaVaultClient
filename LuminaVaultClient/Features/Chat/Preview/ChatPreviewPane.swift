// LuminaVaultClient/LuminaVaultClient/Features/Chat/Preview/ChatPreviewPane.swift
//
// The preview itself. Beside the transcript in a regular-width layout, in a
// sheet in a compact one — `ChatView` decides which; this only renders.

import SwiftUI

struct ChatPreviewPane: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.openURL) private var openURL

    let target: ChatPreviewTarget
    @State var model: ChatPreviewContentModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(palette.surfaceStroke)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LVSpacing.md)
            }
        }
        .background(palette.backgroundBase.opacity(0.6))
        // Keyed on the address, so tapping a second target reloads, and a
        // late answer for the first is dropped by the model.
        .task(id: target.address) {
            await model.load(target)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview: \(target.label)")
    }

    private var header: some View {
        HStack(spacing: LVSpacing.sm) {
            Text(target.label)
                .lvFont(.microTag)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.leading, LVSpacing.md)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, LVSpacing.xl)

        case let .text(title, body, link):
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(body)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                if let link { openLink(link) }
            }

        case let .image(title, url):
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary)
                // Artifacts are harvested references, not stored bytes, so the
                // image may be gone from wherever Hermes put it.
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFit()
                    case .failure: Text("This image is no longer available.").foregroundStyle(palette.textSecondary)
                    default: ProgressView()
                    }
                }
                .clipShape(.rect(cornerRadius: LVRadius.md))
                .accessibilityLabel(title)
                openLink(url)
            }

        case let .link(url):
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text(url.host() ?? url.absoluteString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .textSelection(.enabled)
                openLink(url)
            }

        case let .failed(message):
            Text(message).foregroundStyle(palette.textSecondary)

        case .unavailable:
            Text("This preview isn't available in this build.").foregroundStyle(palette.textSecondary)
        }
    }

    /// Leaving the app is always the user's decision.
    private func openLink(_ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square").lvFont(.microTag)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
    }
}
