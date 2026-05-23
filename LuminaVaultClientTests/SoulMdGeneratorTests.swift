// LuminaVaultClient/LuminaVaultClientTests/SoulMdGeneratorTests.swift
// HER-100 — pure-function rendering of quiz answers into SOUL.md.

import XCTest
@testable import LuminaVaultClient

final class SoulMdGeneratorTests: XCTestCase {
    func testRenderIncludesEveryPickedSection() {
        var answers = SoulQuizAnswers()
        answers.tone = .warm
        answers.priorities = [.focus, .health]
        answers.format = .prose
        answers.length = .long
        answers.emojis = true
        answers.voiceSamples = ["Hey friend!", "  ", "Catch you later."]

        let md = SoulMdGenerator.render(answers)

        XCTAssertTrue(md.contains("## Tone"))
        XCTAssertTrue(md.contains("**warm**"))
        XCTAssertTrue(md.contains("## What matters to me"))
        XCTAssertTrue(md.contains("- Focus"))
        XCTAssertTrue(md.contains("- Health"))
        XCTAssertTrue(md.contains("Format: **prose**"))
        XCTAssertTrue(md.contains("Length: **long**"))
        XCTAssertTrue(md.contains("Emojis: **yes**"))
        XCTAssertTrue(md.contains("> Hey friend!"))
        XCTAssertTrue(md.contains("> Catch you later."))
        // Blank/whitespace-only samples are pruned.
        XCTAssertFalse(md.contains(">  \n"))
        XCTAssertTrue(md.hasSuffix("\n"))
    }

    func testRenderHandlesEmptyAnswersGracefully() {
        let md = SoulMdGenerator.render(SoulQuizAnswers())
        XCTAssertTrue(md.contains("no preference"))
        XCTAssertTrue(md.contains("no priorities"))
        // The "How I talk" section is omitted entirely when no voice samples
        // survive trimming, instead of rendering an empty stub.
        XCTAssertFalse(md.contains("## How I talk"))
    }

    func testOtherPriorityFlowsAsFreeText() {
        var answers = SoulQuizAnswers()
        answers.priorities = [.creative, .other]
        answers.otherPriority = "  woodworking on weekends  "
        let md = SoulMdGenerator.render(answers)
        XCTAssertTrue(md.contains("- Creative"))
        XCTAssertTrue(md.contains("- woodworking on weekends"))
        // Whitespace-padded user input is trimmed.
        XCTAssertFalse(md.contains("-   woodworking"))
    }
}
