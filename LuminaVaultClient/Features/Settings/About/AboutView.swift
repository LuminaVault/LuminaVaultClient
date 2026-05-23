// LuminaVaultClient/LuminaVaultClient/Features/Settings/About/AboutView.swift
//
// HER-298 — minimal About pane surfaced from Settings root. Houses the
// app version + brand presence + social links + Apple-HIG required
// "Rate" entry point + Terms / Privacy / support contact.
//
// `@Environment(\.requestReview)` is the SwiftUI 16+ wrapper around the
// StoreKit review prompt. Apple silently throttles past the 3/year cap
// so we don't need to track local state — the button is always tappable.

import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.lvPalette) private var palette

    var body: some View {
        List {
            heroSection
            rateSection
            followSection
            connectSection
            legalSection
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            VStack(spacing: 12) {
                HermieMascotView(state: .idle, size: 96, fallbackImageName: "OnboardingMascot")
                VStack(spacing: 4) {
                    Text("LuminaVault")
                        .font(.system(size: 22, weight: .heavy))
                    Text("An AI that actually knows you.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(Config.appVersionString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Rate

    private var rateSection: some View {
        Section {
            Button {
                // Apple's review action is async-callable and idempotent.
                // No-op past the 3/year cap; safe to invoke from any tap.
                requestReview()
            } label: {
                Label("Rate LuminaVault", systemImage: "star")
                    .foregroundStyle(.primary)
            }
        } footer: {
            Text("Apple shows the review prompt at most 3 times per year per device.")
                .font(.caption)
        }
    }

    // MARK: - Social

    private var followSection: some View {
        Section("Follow Lumina") {
            Link(destination: Config.tiktokURL) {
                Label("TikTok", systemImage: "music.note")
            }
            Link(destination: Config.xProfileURL) {
                Label("X (Twitter)", systemImage: "x.circle")
            }
            Link(destination: Config.instagramURL) {
                Label("Instagram", systemImage: "camera.aperture")
            }
        }
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section("Connect") {
            Link(destination: Config.websiteURL) {
                Label("luminavault.com", systemImage: "globe")
            }
            if let mailto = URL(string: "mailto:\(Config.supportEmail)") {
                Link(destination: mailto) {
                    Label(Config.supportEmail, systemImage: "envelope")
                }
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section("Legal") {
            Link(destination: Config.termsOfServiceURL) {
                Label("Terms of Service", systemImage: "doc.text")
            }
            Link(destination: Config.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }
}
