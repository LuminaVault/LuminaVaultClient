// LuminaVaultClient/LuminaVaultClientTests/WikilinkParserTests.swift
import Foundation
@testable import LuminaVaultClient
import XCTest

final class WikilinkParserTests: XCTestCase {
    func testParsesNoteLinks() {
        let links = WikilinkParser.links(in: "Read [[Project Plan]] next.")

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "Project Plan")
        XCTAssertEqual(links.first?.kind, .note("Project Plan"))
    }

    func testParsesAliasedNoteLinks() {
        let links = WikilinkParser.links(in: "Read [[notes/project-plan|the plan]].")

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "the plan")
        XCTAssertEqual(links.first?.kind, .note("notes/project-plan"))
    }

    func testParsesMemoryLinks() {
        let id = UUID()
        let links = WikilinkParser.links(in: "Source [[memory:\(id.uuidString)]].")

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "Memory")
        XCTAssertEqual(links.first?.kind, .memory(id))
    }

    func testParsesAliasedMemoryLinks() {
        let id = UUID()
        let links = WikilinkParser.links(in: "Source [[memory:\(id.uuidString)|original memory]].")

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "original memory")
        XCTAssertEqual(links.first?.kind, .memory(id))
    }

    func testIgnoresMalformedMemoryLinks() {
        let links = WikilinkParser.links(in: "Broken [[memory:not-a-uuid]].")

        XCTAssertTrue(links.isEmpty)
    }

    func testRendersCustomMarkdownLinksRoundTrip() throws {
        let id = UUID()
        let rendered = WikilinkParser.markdownByRenderingLinks(
            in: "See [[Project Plan]] and [[memory:\(id.uuidString)|source]]."
        )

        XCTAssertFalse(rendered.contains("[[Project Plan]]"))
        XCTAssertTrue(rendered.contains("luminavault-wikilink://note"))
        XCTAssertTrue(rendered.contains("luminavault-wikilink://memory"))

        let firstURL = try XCTUnwrap(rendered.urls.first)
        let link = try XCTUnwrap(WikilinkParser.link(from: firstURL))
        XCTAssertEqual(link.kind, .note("Project Plan"))
    }
}

private extension String {
    var urls: [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(startIndex ..< endIndex, in: self)
        return detector?.matches(in: self, range: range).compactMap(\.url) ?? []
    }
}
