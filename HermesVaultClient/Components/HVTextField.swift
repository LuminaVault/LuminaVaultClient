// HermesVaultClient/HermesVaultClient/Components/HVTextField.swift
import SwiftUI

struct HVTextField: View {
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
            .foregroundStyle(Color.hvTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.hvGlass)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.hvBorderFocus : Color.hvBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
