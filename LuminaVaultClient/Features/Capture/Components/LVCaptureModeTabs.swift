// LuminaVaultClient/LuminaVaultClient/Features/Capture/Components/LVCaptureModeTabs.swift
//
// HER-305 — three-tab glass-pill selector for Capture mode. Replaces
// the system segmented Picker so the sheet's look is fully native to
// the LuminaVault design language (glass + matched-geometry selection
// pill + cyan glow).

import SwiftUI

struct LVCaptureModeTabs: View {
    @Environment(\.lvPalette) private var palette
    @Namespace private var selectionNS

    @Binding var selected: CaptureSheet.Mode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureSheet.Mode.allCases) { mode in
                tabButton(for: mode)
            }
        }
        .padding(LVSpacing.xs)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .stroke(palette.surfaceStroke, lineWidth: 1)
        }
        .shadow(color: palette.glowPrimary.opacity(0.18), radius: 18)
    }

    @ViewBuilder
    private func tabButton(for mode: CaptureSheet.Mode) -> some View {
        let isSelected = mode == selected
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selected = mode
            }
        } label: {
            HStack(spacing: LVSpacing.xs) {
                LVIconView(
                    mode.icon,
                    size: 14,
                    tint: isSelected ? palette.textPrimary : palette.textSecondary
                )
                Text(mode.label)
                    .lvFont(.fieldLabel)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.vertical, LVSpacing.sm)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.glowPrimary.opacity(0.22),
                                    palette.glowSecondary.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Capsule()
                                .stroke(palette.glowPrimary.opacity(0.55), lineWidth: 1)
                        }
                        .shadow(color: palette.glowPrimary.opacity(0.45), radius: 10)
                        .matchedGeometryEffect(id: "selectionPill", in: selectionNS)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension CaptureSheet.Mode {
    var icon: LVIcon {
        switch self {
        case .photo: return .photoOnRectangleAngled
        case .text:  return .docText
        case .url:   return .linkCircle
        }
    }
}

#Preview {
    StatefulPreviewWrapper(CaptureSheet.Mode.photo) { binding in
        ZStack {
            Color(LVPalette.cyanGoldDark.backgroundBase).ignoresSafeArea()
            LVCaptureModeTabs(selected: binding)
                .padding()
        }
        .preferredColorScheme(.dark)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
