// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeRecommendationRow.swift
//
// The one thing worth doing next, as a row.
//
// Home offers at most one suggestion plus anything that actually needs
// rescuing (a capture that gave up). More than that and it is a to-do list
// nobody asked for — which is what the Dashboard's panel of counters was.

import SwiftUI

/// Title over subtitle beside a glyph. Shared so a `Button` row and a
/// `NavigationLink` row read identically; the link draws its own chevron.
struct HomeRecommendationLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// A recommendation that opens a sheet rather than pushing a screen, with the
/// chevron a `NavigationLink` would have drawn for it.
struct HomeRecommendationRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                HomeRecommendationLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
