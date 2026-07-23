// LuminaVaultClient/LuminaVaultClient/Features/Capture/Components/LVCaptureToolbar.swift
//
// HER-305 — bottom-anchored toolbar for the Capture sheet. Plain
// Cancel + glowing Save pill. Save is the only place in the sheet
// that uses high-intensity glow — it's the obvious focal point.

import SwiftUI

struct LVCaptureToolbar: View {
    @Environment(\.lvPalette) private var palette

    let canSave: Bool
    let saving: Bool
    let saveLabel: String
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        canSave: Bool,
        saving: Bool,
        saveLabel: String = "Save",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.canSave = canSave
        self.saving = saving
        self.saveLabel = saveLabel
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, LVSpacing.sm)
                .padding(.horizontal, LVSpacing.base)

            Spacer()

            Button(action: onSave) {
                HStack(spacing: LVSpacing.sm) {
                    if saving {
                        ProgressView()
                            .tint(palette.textPrimary)
                    } else {
                        LVIconView(.checkmark, size: 14, tint: palette.textPrimary)
                    }
                    Text(saving ? "Saving…" : saveLabel)
                        .lvFont(.bodyEmphasis)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.vertical, LVSpacing.md)
                .padding(.horizontal, LVSpacing.xl)
            }
            .buttonStyle(.plain)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.glowPrimary.opacity(0.30),
                                palette.glowSecondary.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Capsule()
                    .stroke(palette.glowPrimary.opacity(0.7), lineWidth: 1.2)
            }
            .shadow(color: palette.glowPrimary.opacity(canSave ? 0.55 : 0.0), radius: 18)
            .opacity(canSave ? 1 : 0.4)
            .lvPulse(active: saving)
            .lvGlowPress()
            .disabled(!canSave || saving)
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.md)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.clear, palette.glowPrimary.opacity(0.35), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
        }
    }
}

#Preview {
    ZStack {
        Color(LVPalette.cyanGoldDark.backgroundBase).ignoresSafeArea()
        VStack {
            Spacer()
            LVCaptureToolbar(canSave: true, saving: false, onCancel: {}, onSave: {})
        }
    }
    .preferredColorScheme(.dark)
}
