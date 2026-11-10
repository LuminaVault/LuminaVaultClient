// LuminaVaultClient/LuminaVaultClientTests/SourceChipLabelTests.swift
//
// What a chat source chip says. A chunk hit names its file and section, the
// same as the web chip; a hit with no citation falls back to its first words.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class SourceChipLabelTests: XCTestCase {
    private func hit(content: String = "Show the annual plan first.", citation: MemoryCitationDTO? = nil) -> QueryHitDTO {
        QueryHitDTO(id: UUID(), content: content, distance: 0.1, citation: citation)
    }

    func testChunkHitNamesFileAndInnermostHeading() {
        let citation = MemoryCitationDTO(
            chunkID: "c1", documentID: "d1", path: "notes/pricing.md",
            headingPath: ["Pricing pages", "Anchors"], startLine: 5, endLine: 5
        )
        XCTAssertEqual(SourceChipLabel.text(for: hit(citation: citation)), "pricing.md › Anchors")
    }

    func testChunkHitWithoutHeadingsNamesTheFile() {
        let citation = MemoryCitationDTO(chunkID: "c1", documentID: "d1", path: "inbox.md", startLine: 1, endLine: 3)
        XCTAssertEqual(SourceChipLabel.text(for: hit(citation: citation)), "inbox.md")
    }

    func testHitWithoutCitationShowsItsFirstWords() {
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(SourceChipLabel.text(for: hit(content: long)), String(repeating: "a", count: 40))
    }

    func testCitationWithoutPathShowsFirstWords() {
        let citation = MemoryCitationDTO(chunkID: "c1", documentID: "d1", startLine: 1, endLine: 1)
        XCTAssertEqual(SourceChipLabel.text(for: hit(content: "short", citation: citation)), "short")
    }

    func testEmptyHeadingNamesTheFileAlone() {
        let citation = MemoryCitationDTO(
            chunkID: "c1", documentID: "d1", path: "inbox.md", headingPath: [""], startLine: 1, endLine: 1
        )
        XCTAssertEqual(SourceChipLabel.text(for: hit(citation: citation)), "inbox.md")
    }

    func testVoiceOverGetsTheFullPathEveryHeadingAndSpokenLines() {
        let citation = MemoryCitationDTO(
            chunkID: "c1", documentID: "d1", path: "notes/pricing.md",
            headingPath: ["Pricing pages", "Anchors"], startLine: 5, endLine: 9
        )
        XCTAssertEqual(
            SourceChipLabel.accessibilityText(for: hit(citation: citation)),
            "Source: notes/pricing.md, Pricing pages, Anchors, lines 5 to 9"
        )
    }

    func testVoiceOverFallsBackWithTheVisibleLabel() {
        // No path: the chip shows first words, so VoiceOver must not read "L1".
        let citation = MemoryCitationDTO(chunkID: "c1", documentID: "d1", startLine: 1, endLine: 1)
        XCTAssertEqual(SourceChipLabel.accessibilityText(for: hit(content: "short", citation: citation)), "Source: short")
    }
}
