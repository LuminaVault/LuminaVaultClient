// HermesVaultClient/HermesVaultClient/Components/SSORow.swift
import SwiftUI

struct SSORow: View {
    var dividerLabel: String = "or continue with"
    let onSelect: (SSOProvider) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Text(dividerLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hvTextMuted)
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            HStack(spacing: 8) {
                ForEach(SSOProvider.allCases, id: \.self) { provider in
                    SSOButton(provider: provider) { onSelect(provider) }
                }
            }
        }
    }
}
