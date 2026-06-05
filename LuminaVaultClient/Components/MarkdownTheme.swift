// LuminaVaultClient/Components/MarkdownTheme.swift
// MarkdownUI theme mapped to the active LuminaVault palette so rendered notes
// (Vault reader), Chat assistant messages, and Reflect syntheses get full
// GitHub-flavored block styling (heading scale, lists, blockquotes, fenced
// code, tables, rules) instead of the old inline-only AttributedString render.

import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    /// Builds a Theme bound to the supplied palette. Pass the value read from
    /// `\.lvPalette` so the rendered markdown tracks the user's theme + scheme.
    static func luminaVault(_ palette: LVPalette) -> MarkdownUI.Theme {
        MarkdownUI.Theme()
            .text {
                ForegroundColor(palette.textPrimary)
                FontSize(15)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                ForegroundColor(palette.primary)
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(palette.primary) }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 20, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.heavy)
                        FontSize(.em(1.6))
                        ForegroundColor(palette.textPrimary)
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 18, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.35))
                        ForegroundColor(palette.textPrimary)
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 14, bottom: 4)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.15))
                        ForegroundColor(palette.textPrimary)
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .markdownMargin(top: 12, bottom: 4)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        ForegroundColor(palette.textPrimary)
                    }
            }
            .blockquote { configuration in
                configuration.label
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(palette.primary.opacity(0.6))
                            .frame(width: 3)
                    }
                    .markdownTextStyle {
                        ForegroundColor(palette.textSecondary)
                        FontStyle(.italic)
                    }
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        ForegroundColor(palette.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(palette.surfaceStroke, lineWidth: 1)
                    )
                    .markdownMargin(top: 8, bottom: 8)
            }
            .thematicBreak {
                Divider()
                    .overlay(palette.surfaceStroke)
                    .markdownMargin(top: 12, bottom: 12)
            }
    }
}
