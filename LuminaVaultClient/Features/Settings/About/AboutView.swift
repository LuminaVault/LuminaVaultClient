// LuminaVaultClient/LuminaVaultClient/Features/Settings/About/AboutView.swift
//
// HER-298 — minimal About pane surfaced from Settings root. Houses the
// app version + brand presence + social links + Apple-HIG required
// "Rate" entry point + Terms / Privacy / support contact.
//
// Rate section: with an App Store ID configured (`AppStoreID` in Info.plist)
// the row deep-links to the listing's write-review sheet, which always
// works. Without one it falls back to `requestReview()`, which iOS may
// silently ignore. The toggle opts out of the automatic prompt that
// `ReviewPrompter` asks for after a few successful saves.

import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.lvPalette) private var palette
    @AppStorage(ReviewPrompter.Keys.promptsEnabled) private var reviewPromptsEnabled = true

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
            if let writeReviewURL = Config.appStoreWriteReviewURL {
                Link(destination: writeReviewURL) {
                    Label("Rate LuminaVault on the App Store", systemImage: "star")
                }
            } else {
                Button {
                    // No App Store ID yet, so no listing to link to. iOS may
                    // show nothing here (3/year cap).
                    requestReview()
                } label: {
                    Label("Rate LuminaVault", systemImage: "star")
                        .foregroundStyle(.primary)
                }
            }
            Toggle(isOn: $reviewPromptsEnabled) {
                Label("Ask me to rate LuminaVault", systemImage: "hand.wave")
            }
        } footer: {
            Text("When on, LuminaVault may ask for a rating after a few saves to your vault, at most once every four months.")
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
