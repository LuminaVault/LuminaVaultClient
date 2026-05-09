// LuminaVaultClient/LuminaVaultClient/Components/LVButton.swift
import SwiftUI

struct LVButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().progressViewStyle(.circular).tint(.black).scaleEffect(0.85)
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .lvCyan,               location: 0.0),
                        .init(color: .lvBlue,               location: 0.6),
                        .init(color: .lvAmber.opacity(0.7), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .shadow(color: Color.lvCyan.opacity(0.35), radius: 12, y: 4)
            .shadow(color: Color.lvAmber.opacity(0.15), radius: 24, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
