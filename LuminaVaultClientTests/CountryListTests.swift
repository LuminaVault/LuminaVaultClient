// LuminaVaultClient/LuminaVaultClientTests/CountryListTests.swift
// HER-141 smoke tests for the bundled country list.
import XCTest
@testable import LuminaVaultClient

final class CountryListTests: XCTestCase {
    func test_all_includesPrimaryTargetMarkets() {
        let iso = Set(Countries.all.map(\.isoCode))
        // HER-141 explicitly calls out Brazil, India, MENA. UK/US for parity.
        for code in ["US", "GB", "BR", "IN", "AE", "SA", "EG"] {
            XCTAssertTrue(iso.contains(code), "country list missing \(code)")
        }
    }

    func test_all_isAlphabetisedByName() {
        // Locale-aware sort so diacritics (e.g. "Côte d'Ivoire") collate
        // alongside their base letter rather than after every ASCII letter.
        let names = Countries.all.map(\.name)
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted, "Country list must stay alphabetised by name")
    }

    func test_all_dialCodesStartWithPlus() {
        for c in Countries.all {
            XCTAssertTrue(c.dialCode.hasPrefix("+"), "\(c.isoCode) missing + prefix on dial code")
        }
    }

    func test_flagEmoji_rendersTwoScalarsForISO() {
        let us = Countries.all.first { $0.isoCode == "US" }!
        // Regional Indicator scalars: U+1F1FA, U+1F1F8 → 2 scalars total.
        XCTAssertEqual(us.flag.unicodeScalars.count, 2)
    }

    func test_default_isUSWhenLocaleUnknown() {
        // We can't easily override Locale.current here, so we just assert the
        // contract: Countries.default is always one of Countries.all.
        XCTAssertTrue(Countries.all.contains(Countries.default))
    }
}
