// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/Screens/FunnelScreenChrome.swift
//
// HER-287 — shared visual chrome reused across every funnel screen so
// the headline / subhead / CTA spacing stays consistent. Each step
// view composes its own content inside this scaffold.

import SwiftUI

struct FunnelScreenChrome<Content: View>: View {
    @Environment(\.lvPalette) private var palette
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
        // A `ScrollView` whose CTA is pinned via `.safeAreaInset(edge:.bottom)`
        // instead of being a `VStack` sibling. A sibling competes with the
        // ScrollView for the parent's flexible height, and in this funnel that
        // repeatedly collapsed the scroll content to ~0pt (headline + hero
        // vanish, CTA floats up under the progress bar). `safeAreaInset`
        // reserves the CTA's height and lets the ScrollView fill everything
        // else, so the content can never be starved.
        ScrollView {
            VStack(alignment: .leading, spacing: LVSpacing.base) {
                Text(headline)
                    .font(.title.bold())
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(2)
                    .padding(.top, LVSpacing.xl)
                if let subhead {
                    Text(subhead)
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                }
                content()
                    .padding(.top, LVSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LVSpacing.xl)
            .padding(.bottom, LVSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if primaryCTA != nil || secondaryCTA != nil {
                ctaStack
                    .padding(.horizontal, LVSpacing.xl)
                    .padding(.top, LVSpacing.md)
                    .safeAreaPadding(.bottom, LVSpacing.sm)
                    .background {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(palette.glowPrimary.opacity(0.2))
                                .frame(height: 1)
                            Rectangle()
                                .fill(.ultraThinMaterial)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 10) {
            if let label = primaryCTA, let onPrimary {
                Button(action: onPrimary) {
                    Text(label)
                        .font(.headline)
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}