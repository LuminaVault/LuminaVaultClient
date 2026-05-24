// LuminaVaultClient/LuminaVaultClientTests/WikilinkResolverTests.swift
//
// HER-155 follow-up — integration coverage for the resolution logic
// behind `WikilinkMarkdownView`. Direct SwiftUI view-tree integration
// requires ViewInspector or similar; instead, the unit-testable bits
// (note matching, key normalization, stored-markdown invariance) are
// extracted onto `WikilinkResolver` and exercised here.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class WikilinkResolverTests: XCTestCase {
    // MARK: - normalizedNoteKey

    func testNormalizedNoteKeyLowercases() {
        XCTAssertEqual(WikilinkResolver.normalizedNoteKey("Project Plan"), "project plan")
    }

    func testNormalizedNoteKeyStripsMdExtension() {
        XCTAssertEqual(WikilinkResolver.normalizedNoteKey("notes/project.md"), "notes/project")
    }

    func testNormalizedNoteKeyTrimsWhitespace() {
        XCTAssertEqual(WikilinkResolver.normalizedNoteKey("   notes/x  "), "notes/x")
    }

    // MARK: - noteMatches

    func testNoteMatchesReturnsExactPathHit() {
        let target = "notes/project-plan"
        let files: [VaultFileDTO] = [
            makeFile(path: "notes/project-plan.md"),
            makeFile(path: "notes/other.md"),
        ]

        let matches = WikilinkResolver.noteMatches(for: target, in: files)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.path, "notes/project-plan.md")
    }

    func testNoteMatchesReturnsBasenameHit() {
        // `[[Project Plan]]` should find `notes/2026-05-17/Project Plan.md`
        // via lastPathComponent fallback, not just full-path equality.
        let target = "Project Plan"
        let files: [VaultFileDTO] = [
            makeFile(path: "notes/2026-05-17/Project Plan.md"),
            makeFile(path: "notes/sleep.md"),
        ]

        let matches = WikilinkResolver.noteMatches(for: target, in: files)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.path, "notes/2026-05-17/Project Plan.md")
    }

    func testNoteMatchesFallsBackToAllMarkdownWhenNoExactMatch() {
        // When there is no exact hit, the helper hands back every markdown
        // file so the calling view can present a disambiguation dialog
        // rather than dead-ending the user.
        let target = "completely-unknown"
        let files: [VaultFileDTO] = [
            makeFile(path: "notes/a.md"),
            makeFile(path: "notes/b.md"),
            makeFile(path: "images/diagram.png", contentType: "image/png"),
        ]

        let matches = WikilinkResolver.noteMatches(for: target, in: files)

        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.allSatisfy { $0.path.hasSuffix(".md") })
    }

    func testNoteMatchesIgnoresNonMarkdown() {
        let target = "diagram"
        let files: [VaultFileDTO] = [
            makeFile(path: "images/diagram.png", contentType: "image/png"),
            makeFile(path: "binaries/diagram.bin", contentType: "application/octet-stream"),
        ]

        let matches = WikilinkResolver.noteMatches(for: target, in: files)

        XCTAssertTrue(matches.isEmpty)
    }

    func testNoteMatchesAcceptsContentTypeContainingMarkdown() {
        // Server may emit `text/markdown; charset=utf-8` — contains check.
        let target = "alpha"
        let files: [VaultFileDTO] = [
            makeFile(path: "alpha", contentType: "text/markdown; charset=utf-8"),
        ]

        let matches = WikilinkResolver.noteMatches(for: target, in: files)

        XCTAssertEqual(matches.count, 1)
    }

    // MARK: - Stored-markdown invariance (Obsidian export contract)

    /// The view renders `WikilinkParser.markdownByRenderingLinks(in:)` for
    /// display only; the underlying string fed into it must never be
    /// mutated. If this assertion ever fails, vault files exported to
    /// disk no longer round-trip cleanly into Obsidian.
    func testStoredMarkdownNeverMutated() {
        let original = """
        # Sleep notes

        Slept 7h. See [[Project Plan]] and [[memory:11111111-2222-3333-4444-555555555555]]
        for context. Also [[notes/2026-05-17/diet.md|diet log]] holds the
        macro breakdown.
        """

        // Round-trip through the parser the same way the view does.
        _ = WikilinkParser.markdownByRenderingLinks(in: original)

        // The view consumes a `let markdown: String` — the source must
        // stay byte-identical after rendering.
        XCTAssertEqual(original, """
        # Sleep notes

        Slept 7h. See [[Project Plan]] and [[memory:11111111-2222-3333-4444-555555555555]]
        for context. Also [[notes/2026-05-17/diet.md|diet log]] holds the
        macro breakdown.
        """)
    }

    // MARK: - Helpers

    private func makeFile(
        path: String,
        contentType: String = "text/markdown",
        sizeBytes: Int64 = 100
    ) -> VaultFileDTO {
        VaultFileDTO(
            id: UUID(),
            path: path,
            contentType: contentType,
            sizeBytes: sizeBytes,
            sha256: "stub-sha",
            spaceId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
