// LuminaVaultClient/LuminaVaultClientTests/SpaceEditorFormTests.swift
// The rules behind the New Space / Edit Space sheet, and the icon set it
// offers.

@testable import LuminaVaultClient
import Foundation
import XCTest

final class SpaceEditorFormTests: XCTestCase {
    func testCannotSubmitWithoutAName() {
        var form = SpaceEditorForm()
        XCTAssertFalse(form.canSubmit)

        form.name = "   "
        XCTAssertFalse(form.canSubmit, "whitespace is not a name")

        form.name = "Health"
        XCTAssertTrue(form.canSubmit, "a name is all a new space needs")
    }

    func testPayloadTrimsAndDropsAnEmptyCategory() {
        var form = SpaceEditorForm()
        form.name = "  Health \n"
        form.category = "  "

        XCTAssertEqual(
            form.payload,
            SpaceEditorPayload(name: "Health", icon: SpaceIcon.defaultSymbol, category: nil)
        )
    }

    func testEditingKeepsAnIconTheGridDoesNotOffer() {
        // The web app stores its own icon names ("trending-up"). Saving an
        // edit from iOS must not overwrite one of those with a default.
        let space = SpaceDTO(
            id: UUID(), name: "Stocks", slug: "stocks", description: nil, color: nil,
            icon: "trending-up", category: "stocks", noteCount: 0,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        var form = SpaceEditorForm(editing: space)
        XCTAssertNil(form.icon, "nothing in the grid is selected")
        XCTAssertNil(form.payload.icon, "nil tells the server to keep the stored icon")

        form.icon = "globe"
        XCTAssertEqual(form.payload.icon, "globe", "an explicit pick is sent")
    }

    func testEditingSelectsAnIconTheGridOffers() {
        let form = SpaceEditorForm(editing: .stub(name: "AI", slug: "ai"))
        XCTAssertEqual(form.icon, "sparkles")
        XCTAssertEqual(form.name, "AI")
        XCTAssertEqual(form.category, "ai")
    }

    func testSuggestedCategoriesLeaveOutTheAllFilter() {
        XCTAssertEqual(SpaceEditorForm.suggestedCategories(from: [allCategoriesSlug]), [],
                       "no real categories means no chip row at all")
        XCTAssertEqual(SpaceEditorForm.suggestedCategories(from: [allCategoriesSlug, "ai", "work"]),
                       ["ai", "work"])
    }

    // MARK: - Icon set

    func testEveryChoiceDrawsADifferentGlyph() {
        let glyphs = SpaceIcon.choices.map { SpaceIcon.resolve($0.symbol) }
        XCTAssertEqual(Set(glyphs).count, SpaceIcon.choices.count,
                       "two choices that look the same on the card are one choice")
    }

    func testNoChoiceFallsBackToTheUnknownGlyph() {
        let fallback = SpaceIcon.resolve("not-a-real-icon")
        for choice in SpaceIcon.choices {
            XCTAssertNotEqual(SpaceIcon.resolve(choice.symbol), fallback, choice.symbol)
        }
    }

    func testChoicesAreUniqueAndIncludeTheDefault() {
        let symbols = SpaceIcon.choices.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertTrue(SpaceIcon.isChoice(SpaceIcon.defaultSymbol))
        XCTAssertFalse(SpaceIcon.isChoice(nil))
    }

    func testSeededSpaceIconsNoLongerShareTheFallback() {
        // "sparkles" is the icon of the AI space every new vault starts with.
        let fallback = SpaceIcon.resolve(nil)
        for symbol in ["sparkles", "globe", "music.note", "book.fill"] {
            XCTAssertNotEqual(SpaceIcon.resolve(symbol), fallback, symbol)
        }
    }
}
