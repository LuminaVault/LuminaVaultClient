// LuminaVaultClient/LuminaVaultClient/Components/OTPFieldRow.swift
import SwiftUI

struct OTPFieldRow: View {
    @Binding var code: String
    var length: Int = 6
    var accentColor: Color = .lvCyan

    @FocusState private var focused: Bool

    private var digits: [String] {
        let chars = Array(code.prefix(length))
        return (0..<length).map { i in i < chars.count ? String(chars[i]) : "" }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<length, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.lvGlass)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    index == code.count ? accentColor.opacity(0.6) : Color.lvBorder,
                                    lineWidth: index == code.count ? 1.5 : 1
                                )
                        )
                    Text(digits[index])
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 40, height: 48)
            }
        }
        .overlay(
            TextField("", text: $code)
                .keyboardType(.numberPad)
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
