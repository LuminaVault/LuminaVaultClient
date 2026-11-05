// LuminaVaultClient/LuminaVaultClientTests/ProminentButtonContrastTests.swift
//
// `.lvProminent` draws `palette.onPrimary` on `palette.primary`, so that pair
// has to be readable in every theme and scheme. WCAG AA for normal text is 4.5:1.

import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ProminentButtonContrastTests: XCTestCase {
    func testOnPrimaryIsReadableOnPrimaryInEveryPalette() async throws {
        for theme in LVTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.palette(for: scheme)
                let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
                // `system` uses Color.accentColor, which converts to UIKit's system
                // blue here rather than the AccentColor asset the app draws.
                let primary = theme == .system
                    ? try XCTUnwrap(UIColor(named: "AccentColor"))
                    : UIColor(palette.primary)
                let ratio = Self.contrast(
                    UIColor(palette.onPrimary).resolvedColor(with: traits),
                    primary.resolvedColor(with: traits)
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme) \(scheme)")
            }
        }
    }

    private static func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> Double {
        var (red, green, blue, alpha) = (CGFloat.zero, CGFloat.zero, CGFloat.zero, CGFloat.zero)
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
