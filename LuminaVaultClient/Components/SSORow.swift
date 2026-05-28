// LuminaVaultClient/LuminaVaultClient/Components/SSORow.swift
import SwiftUI

/// HER-209: Apple Sign-In is the primary SSO CTA (full-width, labelled),
/// matching App Store §4.8 + Apple HIG. Google + X drop below as compact
/// chips, and only render if their respective client IDs are configured at
/// build time — non-functional third-party buttons would mislead users and
/// risk §4.8 review interpretation.
struct SSORow: View {
    var dividerLabel: String = "or continue with"
    let onSelect: (SSOProvider) -> Void

    private var thirdPartyProviders: [SSOProvider] {
        var providers: [SSOProvider] = []
        if Config.googleClientID != nil { providers.append(.google) }
        if Config.xClientID != nil { providers.append(.x) }
        return providers
    }

    var body: some View {
        VStack(spacing: LVSpacing.base) {
            HStack(spacing: LVSpacing.md) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Text(dividerLabel)
                    .font(LVTypography.microTag.font.weight(.regular))
                    .foregroundStyle(Color.lvTextMuted)
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            SSOButton(provider: .apple, style: .primary) { onSelect(.apple) }

            if !thirdPartyProviders.isEmpty {
                HStack(spacing: LVSpacing.sm) {
                    ForEach(thirdPartyProviders, id: \.self) { provider in
                        SSOButton(provider: provider, style: .icon) { onSelect(provider) }
                    }
                }
            }
        }
    }
}
