// LuminaVaultClient/LuminaVaultClientTests/BrandIdentityTests.swift
//
// One logo and one mascot: these fail if a second name or a crop rule creeps
// back in. The picture itself is the snapshot suites' job.

import UIKit
import XCTest

@testable import LuminaVaultClient

final class BrandIdentityTests: XCTestCase {
    func testSmallMascotsShowTheHeadCrop() {
        XCTAssertEqual(HermieMascotArt.recommended(for: 56), .head)
        XCTAssertEqual(HermieMascotArt.recommended(for: 95), .head)
    }

    func testLargeMascotsShowTheFullFigure() {
        XCTAssertEqual(HermieMascotArt.recommended(for: 96), .full)
        XCTAssertEqual(HermieMascotArt.recommended(for: 220), .full)
    }

    func testEveryCropAndTheLogoResolve() {
        for art in HermieMascotArt.allCases {
            XCTAssertNotNil(UIImage(named: art.rawValue), art.rawValue)
        }
        XCTAssertNotNil(UIImage(named: "LogoMark"))
    }

    func testRetiredNamesAreGone() {
        for name in [
            "WingedScroll", "OnboardingLogo1", "LaunchMark", "OnboardingMascot",
            "Lumina/Mascot/hermie-hero", "Lumina/Mascot/mascot_premium_1",
            "Lumina/Mascot/winged-scroll-vault", "Lumina/Icons/shield-brain",
        ] {
            XCTAssertNil(UIImage(named: name), name)
        }
    }

    func testWingedIconsDrawSymbolsNotRasterArt() {
        let icons: [LVIcon] = [.scrollWinged, .heartWinged, .shieldBrain, .skeletonKeyPremium]
        for icon in icons {
            XCTAssertNil(icon.customAssetName, "\(icon)")
        }
    }
}
