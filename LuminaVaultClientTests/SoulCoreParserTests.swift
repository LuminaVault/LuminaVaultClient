// LuminaVaultClient/LuminaVaultClientTests/SoulCoreParserTests.swift
//
// Template v2 — parse/assemble round trips around the locked core covenant.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class SoulCoreParserTests: XCTestCase {
    private let core = """
    <!-- lv:core:v1:start -->
    ## Core covenant (managed by LuminaVault)

    - Every link is saved to the vault.
    <!-- lv:core:v1:end -->
    """

    private var doc: String {
        """
        ---
        version: 2
        username: u
        ---

        # SOUL.md

        \(core)

        ## Identity

        I am Hermes.
        """
    }

    func testParseSplitsAroundCore() {
        let parts = SoulCoreParser.parse(doc)
        XCTAssertEqual(parts.core, core)
        XCTAssertTrue(parts.prefix.contains("# SOUL.md"))
        XCTAssertTrue(parts.editable.hasPrefix("## Identity"))
        XCTAssertFalse(parts.editable.contains("lv:core"))
    }

    func testParseWithoutCoreReturnsWholeDocEditable() {
        let legacy = "# SOUL.md\n\nfree-form"
        let parts = SoulCoreParser.parse(legacy)
        XCTAssertNil(parts.core)
        XCTAssertEqual(parts.editable, legacy)
        XCTAssertEqual(parts.prefix, "")
    }

    func testAssembleRoundTripsUnchangedEditable() {
        let parts = SoulCoreParser.parse(doc)
        XCTAssertEqual(SoulCoreParser.assemble(parts, editable: parts.editable), doc)
    }

    func testAssembleWithEditedEditable() {
        let parts = SoulCoreParser.parse(doc)
        let out = SoulCoreParser.assemble(parts, editable: "## Mine\n\nnew content")
        XCTAssertTrue(out.contains(core))
        XCTAssertTrue(out.hasSuffix("## Mine\n\nnew content"))
        XCTAssertTrue(out.hasPrefix("---\n"))
    }

    func testParseToleratesFutureCoreVersion() {
        let v2doc = "# SOUL.md\n\n<!-- lv:core:v2:start -->\nnewer\n<!-- lv:core:v2:end -->\n\nrest"
        let parts = SoulCoreParser.parse(v2doc)
        XCTAssertNotNil(parts.core)
        XCTAssertEqual(parts.editable, "rest")
    }

    func testComposeRequestMappingFromAnswers() {
        var answers = SoulQuizAnswers()
        answers.tone = .dry
        answers.priorities = [.health, .focus]
        answers.otherPriority = "  bonsai  "
        answers.format = .prose
        answers.length = .long
        answers.emojis = true
        answers.voiceSamples = ["yo"]

        let req = SoulComposeRequest(from: answers, dryRun: true)
        XCTAssertEqual(req.tone, .dry)
        XCTAssertEqual(req.priorities, [.focus, .health], "stable declaration order")
        XCTAssertEqual(req.otherPriority, "bonsai")
        XCTAssertEqual(req.format, .prose)
        XCTAssertEqual(req.length, .long)
        XCTAssertEqual(req.emojis, true)
        XCTAssertEqual(req.voiceSamples, ["yo"])
        XCTAssertEqual(req.dryRun, true)
        XCTAssertNil(req.agentName)
    }
}
