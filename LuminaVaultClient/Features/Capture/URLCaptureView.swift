// LuminaVaultClient/LuminaVaultClient/Features/Capture/URLCaptureView.swift
//
// HER-257 / HER-305 — Link mode body. Glass cards for URL, optional
// note, and Space picker. URL field uses the monospaced typography
// token so links read as code-style data, not body copy.

import LuminaVaultShared
import SwiftUI

struct URLCaptureView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: URLCaptureViewModel
    @FocusState private var urlFocused: Bool

    init(viewModel: URLCaptureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LVSpacing.lg) {
                urlCard
                noteCard
                spaceCard
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.top, LVSpacing.sm)
            .padding(.bottom, LVSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await viewModel.loadSpacesIfNeeded() }
        .onAppear { urlFocused = true }
    }

    private var urlCard: some View {
        CaptureCard(
            eyebrowIcon: .linkCircle,
            eyebrowTitle: "Link",
            footer: "Paste an article, X post, or YouTube link. The server resolves OG / oEmbed metadata asynchronously."
        ) {
            TextField("https://…", text: $viewModel.urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lvFont(.mono)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.glowPrimary)
                .focused($urlFocused)
        }
    }

    private var noteCard: some View {
        CaptureCard(eyebrowIcon: .docText, eyebrowTitle: "Note") {
            TextField(
                "Add a note (optional)",
                text: $viewModel.note,
                axis: .vertical
            )
            .lineLimit(2 ... 5)
            .textInputAutocapitalization(.sentences)
            .lvFont(.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.glowPrimary)
        }
    }

    @ViewBuilder
    private var spaceCard: some View {
        if let spaces = viewModel.availableSpaces, !spaces.isEmpty {
            CaptureCard(
                eyebrowIcon: .folder,
                eyebrowTitle: "Space",
                footer: "Pick a Space to file this link into. Unfiled links land at the vault root."
            ) {
                Picker(selection: $viewModel.selectedSpaceID) {
                    Text("Unfiled").tag(UUID?.none)
                    ForEach(spaces, id: \.id) { space in
                        Text(space.name).tag(UUID?.some(space.id))
                    }
                } label: {
                    Text("Space")
                        .lvFont(.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .pickerStyle(.menu)
                .tint(palette.glowPrimary)
            }
        }
    }
}
