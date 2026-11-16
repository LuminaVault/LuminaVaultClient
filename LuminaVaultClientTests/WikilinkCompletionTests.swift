// LuminaVaultClient/LuminaVaultClientTests/WikilinkCompletionTests.swift
// Backlog E5.3 — `[[` suggestions: the pure rules and the suggestion model.
// The cases mirror the web editor's wikilink-complete.test.ts.

import Foundation
import XCTest
@testable import LuminaVaultClient

final class WikilinkCompletionTests: XCTestCase {
    private func ctx(_ text: String) -> WikilinkCompletion.Context? {
        WikilinkCompletion.context(in: text, cursor: text.endIndex)
    }

    func testContextFindsAnOpenLink() {
        XCTAssertEqual(ctx("See [[Wee")?.query, "Wee")
        XCTAssertEqual(ctx("[[")?.query, "")
        XCTAssertEqual(ctx("first line\n[[On")?.query, "On")
        XCTAssertEqual(ctx("[[One]] then [[Tw")?.query, "Tw")
    }

    func testContextSplitsNoteAndHeading() {
        let c = ctx("x [[Plan#Go")
        XCTAssertEqual(c?.note, "Plan")
        XCTAssertEqual(c?.heading, "Go")
    }

    func testContextIgnoresClosedLinksAliasesAndOtherLines() {
        XCTAssertNil(ctx("[[Done]] and more"))
        XCTAssertNil(ctx("[[Note|alias"))
        XCTAssertNil(ctx("a [b] c"))
        XCTAssertNil(ctx("[[a [x"))
        XCTAssertNil(ctx("[[open\nnext line"))
    }

    private let paths = [
        "inbox/Weekly-sync.md", "work/Sync-notes.md", "work/plan.md", "ideas/plan.md",
        "inbox/photo.jpg", "daily/2026-11-16.md",
    ]

    func testRankNotes() {
        let out = WikilinkCompletion.rankNotes(paths, query: "sync")
        XCTAssertEqual(out.map(\.path), ["work/Sync-notes.md", "inbox/Weekly-sync.md"])
        XCTAssertEqual(out.first, .init(label: "Sync-notes", detail: "work", path: "work/Sync-notes.md"))
        XCTAssertEqual(WikilinkCompletion.rankNotes(paths, query: "daily").map(\.path), ["daily/2026-11-16.md"])
        XCTAssertTrue(WikilinkCompletion.rankNotes(paths, query: "photo").isEmpty)
        XCTAssertEqual(WikilinkCompletion.rankNotes(paths, query: "", limit: 3).count, 3)
    }

    func testClashingNamesLinkByPath() {
        let labels = WikilinkCompletion.rankNotes(paths, query: "plan").map(\.label).sorted()
        XCTAssertEqual(labels, ["ideas/plan", "work/plan"])
    }

    func testHeadingsSkipCodeFences() {
        let md = "# Title\n\ntext\n## Next steps ##\n```\n# not a heading\n```\n### Done\n#nope"
        XCTAssertEqual(WikilinkCompletion.headings(of: md), ["Title", "Next steps", "Done"])
        XCTAssertEqual(
            WikilinkCompletion.rankHeadings(["Goals", "Next goals", "Risks", "Goals"], prefix: "go"),
            ["Goals", "Next goals"]
        )
    }

    func testApplyClosesTheLinkOnce() throws {
        let text = "See [[pl"
        let (out, offset) = try WikilinkCompletion.apply(
            target: "plan", to: text, context: XCTUnwrap(ctx(text)), cursor: text.endIndex
        )
        XCTAssertEqual(out, "See [[plan]]")
        XCTAssertEqual(offset, out.count)

        let closed = "See [[pl]] more"
        let cursor = try XCTUnwrap(closed.range(of: "]]")?.lowerBound)
        let c = try XCTUnwrap(WikilinkCompletion.context(in: closed, cursor: cursor))
        let (out2, offset2) = WikilinkCompletion.apply(target: "plan", to: closed, context: c, cursor: cursor)
        XCTAssertEqual(out2, "See [[plan]] more")
        XCTAssertEqual(offset2, "See [[plan]]".count)
    }
}

@MainActor
final class WikilinkSuggestionModelTests: XCTestCase {
    private func file(_ path: String) -> VaultFileDTO {
        VaultFileDTO(id: UUID(), path: path, contentType: "text/markdown", sizeBytes: 1, sha256: "")
    }

    private func client(_ paths: [String]) -> MockVaultClient {
        let mock = MockVaultClient()
        mock.listFilesResult = .success(VaultFileListResponse(files: paths.map(file), limit: 50))
        return mock
    }

    func testSuggestsNotesWithTheQuery() async {
        let mock = client(["work/roadmap.md", "inbox/plan.md", "inbox/roadmap.jpg"])
        let model = WikilinkSuggestionModel(vaultClient: mock, debounce: .zero)
        let text = "See [[road"
        model.update(text: text, cursor: text.endIndex)
        await model.settle()
        XCTAssertEqual(model.suggestions.map(\.label), ["roadmap"])
        XCTAssertEqual(model.suggestions.first?.detail, "work")
        XCTAssertEqual(mock.listFilesCalls.last?.q, "road")
        XCTAssertEqual(mock.listFilesCalls.last?.limit, 50)

        let accepted = model.accept(model.suggestions[0], text: text, cursor: text.endIndex)
        XCTAssertEqual(accepted?.0, "See [[roadmap]]")
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testSuggestsHeadingsAfterHash() async {
        let mock = client(["work/roadmap.md"])
        mock.readFileResult = .success((Data("# Roadmap\n## Goals\n## Risks\n".utf8), "text/markdown"))
        let model = WikilinkSuggestionModel(vaultClient: mock, debounce: .zero)
        let text = "[[roadmap#ri"
        model.update(text: text, cursor: text.endIndex)
        await model.settle()
        XCTAssertEqual(model.suggestions.map(\.label), ["Risks"])
        XCTAssertEqual(
            model.accept(model.suggestions[0], text: text, cursor: text.endIndex)?.0,
            "[[roadmap#Risks]]"
        )
    }

    func testLeavingTheLinkClearsSuggestions() async {
        let mock = client(["work/roadmap.md"])
        let model = WikilinkSuggestionModel(vaultClient: mock, debounce: .zero)
        let text = "[[ro"
        model.update(text: text, cursor: text.endIndex)
        await model.settle()
        XCTAssertFalse(model.suggestions.isEmpty)
        model.update(text: text + "]] done", cursor: (text + "]] done").endIndex)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testFailureShowsNothing() async {
        let mock = MockVaultClient()
        mock.listFilesResult = .failure(URLError(.notConnectedToInternet))
        let model = WikilinkSuggestionModel(vaultClient: mock, debounce: .zero)
        model.update(text: "[[a", cursor: "[[a".endIndex)
        await model.settle()
        XCTAssertTrue(model.suggestions.isEmpty)
    }
}
