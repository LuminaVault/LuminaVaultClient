// LuminaVaultClient/LuminaVaultClient/Components/LVSecureField.swift
import SwiftUI

struct LVSecureField: View {

    @Environment(\.lvPalette) private var palette

    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType? = .password

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                } else {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                }
            }
            .font(LVTypography.caption.font)
            .foregroundStyle(palette.textPrimary)
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Button { revealed.toggle() } label: {
                // HER-291: kept as Image — runtime symbol name (and eye.slash not in LVIcon)
                Image(systemName: revealed ? "eye" : "eye.slash")
                    .font(.system(size: 14)) // TODO HER-icon-tokens: scope deferred per HER-289
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
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
