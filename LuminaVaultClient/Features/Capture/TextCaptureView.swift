// LuminaVaultClient/LuminaVaultClient/Features/Capture/TextCaptureView.swift
//
// HER-256 / HER-305 — Text mode body. Single large glass card for the
// body field + a smaller card for the location toggle. Toolbar lives
// in `CaptureSheet`.

import SwiftUI

struct TextCaptureView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: TextCaptureViewModel
    @FocusState private var bodyFocused: Bool

    init(viewModel: TextCaptureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LVSpacing.lg) {
                bodyCard
                spaceCard
                locationCard
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.top, LVSpacing.sm)
            .padding(.bottom, LVSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { bodyFocused = true }
        .task { await viewModel.loadSpacesIfNeeded() }
    }

    @ViewBuilder
    private var spaceCard: some View {
        if let spaces = viewModel.availableSpaces, !spaces.isEmpty {
            CaptureCard(
                eyebrowIcon: .folder,
                eyebrowTitle: "Space",
                footer: "Pick a Space to file this note into. Unfiled notes land at the vault root."
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

    private var bodyCard: some View {
        CaptureCard(
            eyebrowIcon: .docText,
            eyebrowTitle: "Memory",
            footer: "Plain text. Saves directly to your memory vault — no synthesis, no editing flow."
        ) {
            TextField(
                "What's on your mind?",
                text: $viewModel.content,
                axis: .vertical
            )
            .lineLimit(6 ... 14)
            .textInputAutocapitalization(.sentences)
            .lvFont(.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.glowPrimary)
            .focused($bodyFocused)
            .frame(minHeight: 140, alignment: .topLeading)
        }
    }

    private var locationCard: some View {
        CaptureCard(
            eyebrowIcon: .location,
            eyebrowTitle: "Location",
            footer: "Off by default. Turning it on sends one location fix and the place name with this memory."
        ) {
            Toggle(isOn: $viewModel.locationEnabled) {
                Text("Tag with current location")
                    .lvFont(.body)
                    .foregroundStyle(palette.textPrimary)
            }
            .tint(palette.glowPrimary)
        }
    }
}
