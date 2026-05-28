// LuminaVaultClient/LuminaVaultClient/Features/Capture/CapturePhotosView.swift
//
// HER-34 / HER-305 — sheet body for the "+" FAB's Photos mode. Rebuilt
// as a stack of glass cards on the cinematic shell; toolbar lives in
// `CaptureSheet` so this view focuses on content only.

import PhotosUI
import SwiftUI

struct CapturePhotosView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: CapturePhotosViewModel

    init(viewModel: CapturePhotosViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LVSpacing.lg) {
                pickerCard
                if !viewModel.loadedItems.isEmpty {
                    capturesCard
                    spaceCard
                    locationCard
                }
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.top, LVSpacing.sm)
            .padding(.bottom, LVSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await viewModel.loadSpacesIfNeeded() }
    }

    private var pickerCard: some View {
        CaptureCard(
            eyebrowIcon: .photoOnRectangleAngled,
            eyebrowTitle: "Photos",
            footer: "HEIC and JPEG both upload losslessly. Captures sync when you're online."
        ) {
            PhotosPicker(
                selection: $viewModel.pickerItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: LVSpacing.sm) {
                    LVIconView(.plus, size: 14, tint: palette.glowPrimary)
                    Text(viewModel.loadedItems.isEmpty
                        ? "Pick photos"
                        : "Pick more (\(viewModel.loadedItems.count) selected)")
                        .lvFont(.bodyEmphasis)
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LVSpacing.md)
            }
            .buttonStyle(.plain)
            .lvGlowStroke(cornerRadius: LVRadius.pill, intensity: 0.55)
            .lvGlowPress()
        }
    }

    private var capturesCard: some View {
        CaptureCard(eyebrowIcon: .docOnDoc, eyebrowTitle: "Captures") {
            VStack(spacing: LVSpacing.md) {
                ForEach($viewModel.loadedItems) { $item in
                    HStack(alignment: .top, spacing: LVSpacing.md) {
                        if let uiImage = UIImage(data: item.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: LVRadius.sm,
                                                            style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: LVRadius.sm,
                                                     style: .continuous)
                                        .stroke(palette.glowPrimary.opacity(0.35),
                                                lineWidth: 1)
                                }
                        }
                        TextField(
                            "Add a caption (optional)",
                            text: $item.caption,
                            axis: .vertical
                        )
                        .lineLimit(1 ... 3)
                        .lvFont(.body)
                        .foregroundStyle(palette.textPrimary)
                        .tint(palette.glowPrimary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var spaceCard: some View {
        if let spaces = viewModel.availableSpaces, !spaces.isEmpty {
            CaptureCard(
                eyebrowIcon: .folder,
                eyebrowTitle: "Space",
                footer: "Pick a Space to file this capture into. Unfiled captures land at the vault root."
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

    private var locationCard: some View {
        CaptureCard(
            eyebrowIcon: .location,
            eyebrowTitle: "Location",
            footer: "Off by default. Turning it on sends one location fix and the place name with this capture."
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
