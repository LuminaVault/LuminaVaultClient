// LuminaVaultClient/LuminaVaultClientTests/VaultFileDisplayTests.swift
//
// The vault stores paths; people read titles. `VaultFileDisplay` is the whole
// of that translation — `VaultFileDTO` carries no excerpt or preview — so the
// heuristics are worth pinning down rather than eyeballing in a list.
//
// Relative-date assertions assume an English locale, which is what this
// project's machines and CI run.

import Foundation
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

final class VaultFileDisplayTests: XCTestCase {
    private func file(
        path: String,
        contentType: String = "text/markdown",
        createdAt: Date? = nil,
        metadata: VaultNoteMetadataDTO? = nil
    ) -> VaultFileDTO {
        VaultFileDTO(
            id: UUID(),
            path: path,
            contentType: contentType,
            sizeBytes: 1_024,
            sha256: "deadbeef",
            createdAt: createdAt,
            metadata: metadata
        )
    }

    // MARK: - Title

    func testTitleUsesMetadataTitleWhenPresent() {
        let subject = file(
            path: "2026-09-14-161709-kheprios-com-00e2c497.md",
            metadata: VaultNoteMetadataDTO(title: "Kheprios — pricing")
        )
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Kheprios — pricing")
    }

    func testTitleIgnoresEmptyMetadataTitle() {
        let subject = file(path: "shipping-notes.md", metadata: VaultNoteMetadataDTO(title: ""))
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Shipping notes")
    }

    func testTitleOfPendingLinkIsTheHost() {
        let subject = file(
            path: "2026-09-14-161709-kheprios-com-00e2c497.md",
            metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
        )
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "kheprios.com")
    }

    func testTitleOfPendingLinkHandlesNestedPathsAndSubdomains() {
        let subject = file(
            path: "links/2026-09-14-161709-blog-kheprios-com-00e2c497.md",
            metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
        )
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "blog.kheprios.com")
    }

    func testTitleOfPendingLinkFallsBackWhenBasenameIsNotACaptureName() {
        let subject = file(
            path: "reading-list.md",
            metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
        )
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Reading list")
    }

    func testTitleOfBareUUIDNoteIsDatedNote() {
        let created = Date(timeIntervalSince1970: 1_757_865_429)
        let subject = file(
            path: "9E2C4971-1A2B-4C3D-8E5F-00E2C4971AB2.md",
            createdAt: created
        )
        // Pinned locale and time zone: the string the reader sees is the whole
        // point of the branch, and `hasPrefix("Note · ")` passed for a title
        // that had lost its time.
        let title = VaultFileDisplay.title(
            for: subject,
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(title, "Note · 14 Sept 15:57")
    }

    func testTitleOfBareUUIDNoteWithoutDateIsJustNote() {
        let subject = file(path: "9e2c4971-1a2b-4c3d-8e5f-00e2c4971ab2.md")
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Note")
    }

    func testTitleStripsStampSuffixAndExtension() {
        let subject = file(path: "notes/2026-09-14-161709-quarterly-plan-00e2c497.md")
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Quarterly plan")
    }

    func testTitleOfAnOrdinaryFilename() {
        let subject = file(path: "Spaces/work/meeting-with-ana.md")
        XCTAssertEqual(VaultFileDisplay.title(for: subject), "Meeting with ana")
    }

    // MARK: - Subtitle

    func testSubtitleIsRelativeDate() {
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        let subject = file(path: "note.md", createdAt: now.addingTimeInterval(-2 * 86_400))
        XCTAssertEqual(VaultFileDisplay.subtitle(for: subject, spaceName: nil, now: now), "2 days ago")
    }

    func testSubtitleAppendsSpaceName() {
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        let subject = file(path: "note.md", createdAt: now.addingTimeInterval(-2 * 86_400))
        XCTAssertEqual(
            VaultFileDisplay.subtitle(for: subject, spaceName: "Work", now: now),
            "2 days ago · Work"
        )
    }

    func testSubtitleIsSpaceNameAloneWithoutADate() {
        let subject = file(path: "note.md")
        XCTAssertEqual(VaultFileDisplay.subtitle(for: subject, spaceName: "Work"), "Work")
    }

    func testSubtitleIsEmptyWithNothingToSay() {
        let subject = file(path: "note.md")
        XCTAssertEqual(VaultFileDisplay.subtitle(for: subject, spaceName: nil), "")
    }

    func testSubtitleOfPendingLinkSaysItIsStillArriving() {
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        let subject = file(
            path: "2026-09-14-161709-kheprios-com-00e2c497.md",
            createdAt: now.addingTimeInterval(-60),
            metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
        )
        XCTAssertEqual(
            VaultFileDisplay.subtitle(for: subject, spaceName: "Work", now: now),
            "Fetching the page…"
        )
    }

    // MARK: - Symbol

    func testSymbolForPendingLink() {
        let subject = file(
            path: "2026-09-14-161709-kheprios-com-00e2c497.md",
            metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
        )
        XCTAssertEqual(VaultFileDisplay.symbolName(for: subject), "link")
    }

    func testSymbolForImage() {
        XCTAssertEqual(
            VaultFileDisplay.symbolName(for: file(path: "photo.heic", contentType: "image/heic")),
            "photo"
        )
    }

    func testSymbolForMarkdown() {
        XCTAssertEqual(VaultFileDisplay.symbolName(for: file(path: "note.md")), "doc.text")
    }

    func testSymbolForAnythingElse() {
        XCTAssertEqual(
            VaultFileDisplay.symbolName(for: file(path: "deck.pdf", contentType: "application/pdf")),
            "paperclip"
        )
    }
}
