// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureSheet.swift
//
// HER-256 / HER-305 — wraps the three Capture mode bodies behind a
// glass-pill mode selector and a cinematic shell (aurora backdrop +
// mascot vignette + subtle sparkle field). Save / cancel surfaces via
// a custom bottom toolbar so the mode bodies no longer own their own
// NavigationStack chrome.

import SwiftUI

struct CaptureSheet: View {
    enum Mode: String, CaseIterable, Identifiable, Hashable, Sendable {
        case photo
        case text
        case url
        var id: String { rawValue }
        var label: String {
            switch self {
            case .photo: return "Photos"
            case .text: return "Text"
            case .url: return "Link"
            }
        }
    }

    @Environment(\.lvThemeManager) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .photo

    /// The Capture sheet is an intentionally always-dark cinematic surface
    /// (`.preferredColorScheme(.dark)` below). The inherited `\.lvPalette` is
    /// resolved by the scene root for the *device* color scheme, so on a Light
    /// device it would carry light-mode colors into this force-dark sheet —
    /// painting dark text on dark glass. Re-resolve the active theme for `.dark`
    /// and re-inject it so palette + scheme always agree.
    private var darkPalette: LVPalette {
        (themeManager?.theme ?? .system).palette(for: .dark)
    }

    private let photoViewModel: CapturePhotosViewModel
    private let textViewModel: TextCaptureViewModel
    private let urlViewModel: URLCaptureViewModel

    init(
        photoViewModel: CapturePhotosViewModel,
        textViewModel: TextCaptureViewModel,
        urlViewModel: URLCaptureViewModel
    ) {
        self.photoViewModel = photoViewModel
        self.textViewModel = textViewModel
        self.urlViewModel = urlViewModel
    }

    var body: some View {
        ZStack {
            darkPalette.backgroundBase.ignoresSafeArea()
            AuroraBackdrop()
            CaptureMascotVignette()
            SparkleField(density: 12, maxRadius: 1.4)
                .opacity(0.55)
                .blendMode(.screen)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                LVCaptureModeTabs(selected: $mode)
                    .padding(.horizontal, LVSpacing.base)
                    .padding(.top, LVSpacing.lg)
                    .padding(.bottom, LVSpacing.md)

                ZStack {
                    switch mode {
                    case .photo:
                        CapturePhotosView(viewModel: photoViewModel)
                            .transition(modeTransition)
                    case .text:
                        TextCaptureView(viewModel: textViewModel)
                            .transition(modeTransition)
                    case .url:
                        URLCaptureView(viewModel: urlViewModel)
                            .transition(modeTransition)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mode)
                .frame(maxHeight: .infinity)

                toolbar
            }
        }
        .environment(\.lvPalette, darkPalette)
        .presentationBackground(.clear)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LVRadius.sheet)
        .preferredColorScheme(.dark)
    }

    private var modeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    @ViewBuilder
    private var toolbar: some View {
        switch mode {
        case .photo:
            LVCaptureToolbar(
                canSave: !photoViewModel.loadedItems.isEmpty && !photoViewModel.saving,
                saving: photoViewModel.saving,
                saveLabel: photoViewModel.loadedItems.isEmpty
                    ? "Save"
                    : "Save (\(photoViewModel.loadedItems.count))",
                onCancel: { dismiss() },
                onSave: {
                    Task {
                        await photoViewModel.save()
                        dismiss()
                    }
                }
            )
        case .text:
            LVCaptureToolbar(
                canSave: textViewModel.canSave,
                saving: textViewModel.saving,
                onCancel: { dismiss() },
                onSave: {
                    Task {
                        await textViewModel.save()
                        if textViewModel.toast != nil { dismiss() }
                    }
                }
            )
        case .url:
            LVCaptureToolbar(
                canSave: urlViewModel.canSave,
                saving: urlViewModel.saving,
                onCancel: { dismiss() },
                onSave: {
                    Task {
                        await urlViewModel.save()
                        if urlViewModel.toast != nil { dismiss() }
                    }
                }
            )
        }
    }
}
