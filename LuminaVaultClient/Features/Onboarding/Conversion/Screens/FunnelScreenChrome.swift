// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/Screens/FunnelScreenChrome.swift
//
// HER-287 — shared visual chrome reused across every funnel screen so
// the headline / subhead / CTA spacing stays consistent. Each step
// view composes its own content inside this scaffold.

import SwiftUI

struct FunnelScreenChrome<Content: View>: View {
    let headline: String
    let subhead: String?
    let primaryCTA: String?
    let primaryEnabled: Bool
    let onPrimary: (() -> Void)?
    let secondaryCTA: String?
    let onSecondary: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        headline: String,
        subhead: String? = nil,
        primaryCTA: String? = nil,
        primaryEnabled: Bool = true,
        onPrimary: (() -> Void)? = nil,
        secondaryCTA: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headline = headline
        self.subhead = subhead
        self.primaryCTA = primaryCTA
        self.primaryEnabled = primaryEnabled
        self.onPrimary = onPrimary
        self.secondaryCTA = secondaryCTA
        self.onSecondary = onSecondary
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(headline)
                        .font(.system(size: 28, weight: .heavy))
                        .lineSpacing(2)
                        .padding(.top, 24)
                    if let subhead {
                        Text(subhead)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    content()
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if primaryCTA != nil || secondaryCTA != nil {
                ctaStack
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 10) {
            if let label = primaryCTA, let onPrimary {
                Button(action: onPrimary) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled)
                .opacity(primaryEnabled ? 1.0 : 0.55)
            }
            if let label = secondaryCTA, let onSecondary {
                Button(action: onSecondary) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
