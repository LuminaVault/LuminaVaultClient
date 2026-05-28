// LuminaVaultClient/LuminaVaultClient/Components/OTPFieldRow.swift
import SwiftUI

struct OTPFieldRow: View {

    @Environment(\.lvPalette) private var palette

    @Binding var code: String
    var length: Int = 6
    /// Override the focused-digit accent. When nil, follows the active palette.
    var accentColor: Color? = nil
    /// HER-141: pass `.oneTimeCode` for SMS-autofill; default `nil` preserves
    /// the existing MFA behaviour where the code is typed manually.
    var textContentType: UITextContentType? = nil

    @FocusState private var focused: Bool

    private var resolvedAccent: Color { accentColor ?? palette.primary }

    private var digits: [String] {
        let chars = Array(code.prefix(length))
        return (0..<length).map { i in i < chars.count ? String(chars[i]) : "" }
    }

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            ForEach(0..<length, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: LVRadius.md)
                        .fill(Color.lvGlass)
                        .overlay(
                            RoundedRectangle(cornerRadius: LVRadius.md)
                                .stroke(
                                    index == code.count ? resolvedAccent.opacity(0.6) : palette.surfaceStroke,
                                    lineWidth: index == code.count ? 1.5 : 1
                                )
                        )
                    Text(digits[index])
                        .font(LVTypography.otp.font)
                        .foregroundStyle(resolvedAccent)
                }
                .frame(width: 40, height: 48)
            }
        }
        .overlay(
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(textContentType)
                .focused($focused)
                .opacity(0.01)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(length))
                }
        )
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }
}
