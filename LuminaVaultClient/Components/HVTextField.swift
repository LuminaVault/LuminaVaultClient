// LuminaVaultClient/LuminaVaultClient/Components/LVTextField.swift
import SwiftUI

struct LVTextField: View {
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
            .font(.system(size: 12))
            .foregroundStyle(Color.lvTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.lvGlass)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.lvBorderFocus : Color.lvBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
