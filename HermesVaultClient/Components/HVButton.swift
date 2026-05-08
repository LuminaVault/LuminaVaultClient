// HermesVaultClient/HermesVaultClient/Components/HVButton.swift
import SwiftUI

struct HVButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

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
                        .init(color: .hvCyan,               location: 0.0),
                        .init(color: .hvBlue,               location: 0.6),
                        .init(color: .hvAmber.opacity(0.7), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .shadow(color: Color.hvCyan.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
