// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/AITabHitTestTests.swift
//
// The pure region check behind the AI tab long-press. Geometry comes from the
// trigger spike on iOS 26.2: a 402pt bar with the AI item at 162.5-239.5, and
// a minimized bar that is one 48pt pill at x=28. In landscape on an iPhone 17 the
// bar is 874pt wide with items sized to their labels and centred: Spaces
// 309.7-400.7, AI 404.7-470.7, Brain 474.7-555.
@testable import LuminaVaultClient
import XCTest

final class AITabHitTestTests: XCTestCase {
    private func isAI(x: CGFloat, width: CGFloat = 393) -> Bool {
        AITabHitTest.isAITab(x: x, barWidth: width, tabCount: 5, aiIndex: 2)
    }

    func testCentreOfMiddleSlotIsAI() {
        XCTAssertTrue(isAI(x: 196.5))
    }

    func testNeighbourIsNotAI() {
        XCTAssertFalse(isAI(x: 120))
    }

    func testZeroWidthIsFalse() {
        XCTAssertFalse(isAI(x: 0, width: 0))
        XCTAssertFalse(isAI(x: 196.5, width: 0))
    }

    func testMeasuredAIItemEdgesAreInsideTheRegion() {
        XCTAssertTrue(isAI(x: 162.5, width: 402))
        XCTAssertTrue(isAI(x: 239.5, width: 402))
    }

    func testRightNeighbourIsNotAI() {
        XCTAssertFalse(isAI(x: 300, width: 402))
    }

    func testMinimizedPillIsNotAI() {
        XCTAssertFalse(isAI(x: 28, width: 402))
        XCTAssertFalse(isAI(x: 52, width: 402))
        XCTAssertFalse(isAI(x: 76, width: 402))
    }

    func testLandscapeNeighboursInsideTheMiddleFifthAreNotAI() {
        XCTAssertFalse(isAI(x: 355, width: 874), "centre of Spaces")
        XCTAssertFalse(isAI(x: 391, width: 874), "right of Spaces")
        XCTAssertFalse(isAI(x: 482, width: 874), "left of Brain")
        XCTAssertFalse(isAI(x: 515, width: 874), "centre of Brain")
    }

    func testLandscapeAIItemIsAI() {
        XCTAssertTrue(isAI(x: 404.7, width: 874))
        XCTAssertTrue(isAI(x: 437, width: 874))
        XCTAssertTrue(isAI(x: 470.7, width: 874))
    }

    func testPointsOutsideTheBarAreFalse() {
        XCTAssertFalse(AITabHitTest.isAITab(x: -1, barWidth: 402, tabCount: 5, aiIndex: 0))
        XCTAssertFalse(AITabHitTest.isAITab(x: 402, barWidth: 402, tabCount: 5, aiIndex: 4))
    }

    func testNonFiniteInputDoesNotCrash() {
        XCTAssertFalse(isAI(x: .nan))
        XCTAssertFalse(isAI(x: .infinity))
        XCTAssertFalse(isAI(x: 100, width: .nan))
    }

    func testNoTabsIsFalse() {
        XCTAssertFalse(AITabHitTest.isAITab(x: 100, barWidth: 402, tabCount: 0, aiIndex: 0))
    }
}
