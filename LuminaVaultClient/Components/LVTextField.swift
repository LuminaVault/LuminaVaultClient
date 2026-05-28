// LuminaVaultClient/LuminaVaultClient/Components/LVTextField.swift
import SwiftUI

struct LVTextField: View {

    @Environment(\.lvPalette) private var palette

    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .focused($focused)
            .font(LVTypography.caption.font)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.lvGlass)
            .overlay(
                RoundedRectangle(cornerRadius: LVRadius.md)
                    .stroke(focused ? palette.glowPrimary : palette.surfaceStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
    }
}
