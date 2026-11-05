// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/AITabLongPressTests.swift
//
// The recogniser's rules, checked on real UIKit views: never two on one bar,
// other tabs left alone, and only gestures inside the bar made to wait.
@testable import LuminaVaultClient
import UIKit
import XCTest

@MainActor
final class AITabLongPressTests: XCTestCase {
    private func recognizers(on bar: UITabBar) -> [UIGestureRecognizer] {
        (bar.gestureRecognizers ?? []).filter { $0 is AITabLongPressRecognizer }
    }

    func testAttachingTwiceAddsOneRecognizer() {
        let coordinator = AITabLongPressCoordinator()
        let bar = UITabBar()

        coordinator.attach(to: bar)
        coordinator.attach(to: bar)

        XCTAssertEqual(recognizers(on: bar).count, 1)
    }

    func testARebuiltProbeReplacesTheOldRecognizer() {
        let first = AITabLongPressCoordinator()
        let second = AITabLongPressCoordinator()
        let bar = UITabBar()

        first.attach(to: bar)
        second.attach(to: bar)

        XCTAssertEqual(recognizers(on: bar).count, 1)
        XCTAssertTrue(second.isAttached(to: bar))
        XCTAssertFalse(first.isAttached(to: bar))
    }

    func testDetachingAStaleProbeLeavesTheCurrentRecognizer() {
        let first = AITabLongPressCoordinator()
        let second = AITabLongPressCoordinator()
        let bar = UITabBar()

        first.attach(to: bar)
        second.attach(to: bar)
        first.detach()

        XCTAssertEqual(recognizers(on: bar).count, 1)
    }

    func testMovingToANewBarLeavesNothingOnTheOldOne() {
        let coordinator = AITabLongPressCoordinator()
        let old = UITabBar()
        let new = UITabBar()

        coordinator.attach(to: old)
        coordinator.attach(to: new)

        XCTAssertEqual(recognizers(on: old).count, 0)
        XCTAssertEqual(recognizers(on: new).count, 1)
    }

    func testDetachRemovesTheRecognizer() {
        let coordinator = AITabLongPressCoordinator()
        let bar = UITabBar()

        coordinator.attach(to: bar)
        coordinator.detach()

        XCTAssertEqual(recognizers(on: bar).count, 0)
    }

    func testOnlyATouchOnTheAITabReachesTheRecognizer() throws {
        let coordinator = AITabLongPressCoordinator()
        let bar = UITabBar(frame: CGRect(x: 0, y: 0, width: 402, height: 62))
        coordinator.attach(to: bar)
        let recognizer = try XCTUnwrap(recognizers(on: bar).first)
        func receives(_ x: CGFloat) -> Bool {
            coordinator.gestureRecognizer(recognizer, shouldReceive: TouchAt(x: x))
        }

        XCTAssertTrue(receives(201), "AI")
        XCTAssertFalse(receives(120), "Spaces")
        XCTAssertFalse(receives(282), "Brain")

        bar.frame.size.width = 874
        XCTAssertTrue(receives(437), "AI, landscape")
        XCTAssertFalse(receives(391), "Spaces, landscape")
        XCTAssertFalse(receives(482), "Brain, landscape")
    }

    func testOnlyGesturesInsideTheBarWaitForTheLongPress() throws {
        let coordinator = AITabLongPressCoordinator()
        let screen = UIView()
        let bar = UITabBar()
        let barItem = UIView()
        let content = UIScrollView()
        screen.addSubview(bar)
        screen.addSubview(content)
        bar.addSubview(barItem)
        coordinator.attach(to: bar)
        let recognizer = try XCTUnwrap(recognizers(on: bar).first)

        let onBar = UITapGestureRecognizer()
        bar.addGestureRecognizer(onBar)
        let onItem = UITapGestureRecognizer()
        barItem.addGestureRecognizer(onItem)
        let onScreen = UIPanGestureRecognizer()
        screen.addGestureRecognizer(onScreen)

        XCTAssertTrue(coordinator.gestureRecognizer(recognizer, shouldBeRequiredToFailBy: onBar))
        XCTAssertTrue(coordinator.gestureRecognizer(recognizer, shouldBeRequiredToFailBy: onItem))
        XCTAssertFalse(coordinator.gestureRecognizer(recognizer, shouldBeRequiredToFailBy: content.panGestureRecognizer))
        XCTAssertFalse(coordinator.gestureRecognizer(recognizer, shouldBeRequiredToFailBy: onScreen))
    }
}

/// `UITouch` has no public way to set a location.
private final class TouchAt: UITouch {
    private let x: CGFloat

    init(x: CGFloat) {
        self.x = x
        super.init()
    }

    override func location(in _: UIView?) -> CGPoint {
        CGPoint(x: x, y: 20)
    }
}
