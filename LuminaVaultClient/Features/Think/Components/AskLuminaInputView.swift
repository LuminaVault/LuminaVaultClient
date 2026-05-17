// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/AskLuminaInputView.swift
// HER-37: top "Ask Lumina anything about your life..." input bar.
import SwiftUI

struct AskLuminaInputView: View {
    @Binding var text: String
    var isBusy: Bool
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.lvAmber)
                .font(.system(size: 16, weight: .semibold))
            TextField("Ask Lumina anything about your life…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .disabled(isBusy)
            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(submitColor)
            }
            .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lvGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.lvCyan.opacity(0.25), lineWidth: 1)
        )
    }

    private var submitColor: Color {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy
            ? Color.lvTextSub.opacity(0.4)
            : Color.lvCyan
    }
}
