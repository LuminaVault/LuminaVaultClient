// LuminaVaultClient/LuminaVaultClientTests/LVIconAssetTests.swift
//
// HER-301 — Every `LVIcon` case that claims a `customAssetName` must
// actually resolve to a real `UIImage`. Catches typos in asset paths
// and missing imagesets before they ship as silent SF-Symbol fallbacks.
import XCTest
@testable import LuminaVaultClient

final class LVIconAssetTests: XCTestCase {

    func testAllCustomAssetsResolve() {
        for icon in LVIcon.allCases {
            guard let name = icon.customAssetName else { continue }
            XCTAssertNotNil(
                UIImage(named: name),
                "Missing asset for \(icon) — expected at \(name)",
            )
        }
    }
}
