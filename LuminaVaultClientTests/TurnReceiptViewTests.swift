// LuminaVaultClientTests/TurnReceiptViewTests.swift
//
// The receipt is what tells a user the agent did something. Its whole job is
// to be truthful at a glance, so the interesting cases are the ones where it
// must say *less*: an unknown tool count, and a turn that genuinely ran none.

@testable import LuminaVaultClient
import XCTest

final class TurnReceiptViewTests: XCTestCase {
    private func summary(model: String?, tools: Int?) -> String? {
        TurnReceiptView(modelLabel: model, toolCallCount: tools).summaryForTesting
    }

    func testModelAndToolsReadAsOneLine() {
        XCTAssertEqual(summary(model: "GPT-4o mini", tools: 3), "GPT-4o mini · 3 tools")
    }

    func testSingleToolIsNotPluralized() {
        XCTAssertEqual(summary(model: "Claude Haiku", tools: 1), "Claude Haiku · 1 tool")
    }

    /// "0 tools" under every ordinary answer would be noise, and would read as
    /// a failure rather than as the normal case.
    func testZeroToolsIsNotStated() {
        XCTAssertEqual(summary(model: "GPT-4o mini", tools: 0), "GPT-4o mini")
    }

    /// A turn recorded before the server persisted a count. Unknown must look
    /// the same as none rather than claim zero.
    func testUnknownToolCountIsNotStated() {
        XCTAssertEqual(summary(model: "GPT-4o mini", tools: nil), "GPT-4o mini")
    }

    /// A live-streamed turn knows its tools but not yet its model on some
    /// paths; the receipt should still say what it knows.
    func testToolsWithoutAModelStillRender() {
        XCTAssertEqual(summary(model: nil, tools: 2), "2 tools")
    }

    /// Nothing truthful to say means say nothing — an empty receipt beats a
    /// misleading one.
    func testNothingKnownRendersNothing() {
        XCTAssertNil(summary(model: nil, tools: nil))
        XCTAssertNil(summary(model: "", tools: nil))
    }

    func testAccessibilityLabelSpellsItOut() {
        let view = TurnReceiptView(modelLabel: "GPT-4o mini", toolCallCount: 2)
        XCTAssertEqual(view.accessibilityLabelForTesting, "Answered by GPT-4o mini, using 2 tools")
        let noTools = TurnReceiptView(modelLabel: "GPT-4o mini", toolCallCount: 0)
        XCTAssertEqual(noTools.accessibilityLabelForTesting, "Answered by GPT-4o mini")
    }
}
