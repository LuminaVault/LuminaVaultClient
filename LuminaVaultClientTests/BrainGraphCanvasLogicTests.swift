// The pure rules of the 2D Brain canvas: viewport maths, the automatic fit,
// hit testing, label visibility and placement, and how a press becomes a tap,
// a pan or a point drag. Most cases are ported from the web app's
// `render-2d.test.ts`; the hit floor is 22 pt here (web: 10 px) because a
// finger is wider than a cursor.

import CoreGraphics
import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import SwiftUI
import Testing

/// Every suite of the canvas's pure rules, under one name for `-only-testing`.
@Suite struct BrainGraphCanvasLogicTests {}

// MARK: - Viewport

extension BrainGraphCanvasLogicTests {
    struct BrainGraphViewportTests {
        @Test func mapsWorldToScreenAndBack() {
            let v = BrainGraphViewport(scale: 2, offset: CGPoint(x: 100, y: 50), isAutomatic: false)
            #expect(v.screen(CGPoint(x: 10, y: -5)) == CGPoint(x: 120, y: 40))
            #expect(v.world(CGPoint(x: 120, y: 40)) == CGPoint(x: 10, y: -5))
        }

        @Test func zoomKeepsTheWorldPointUnderTheAnchor() {
            let v = BrainGraphViewport(scale: 1.5, offset: CGPoint(x: 120, y: -40), isAutomatic: true)
            let anchor = CGPoint(x: 200, y: 300)
            let before = v.world(anchor)
            let z = v.zoomed(by: 2, around: anchor)
            #expect(z.scale == 3)
            let after = z.world(anchor)
            #expect(abs(after.x - before.x) < 1e-9)
            #expect(abs(after.y - before.y) < 1e-9)
        }

        @Test func zoomIsClampedBetweenTheLimits() {
            let v = BrainGraphViewport(scale: 1, offset: .zero, isAutomatic: false)
            #expect(BrainGraphViewport.minScale == 0.15)
            #expect(BrainGraphViewport.maxScale == 6)
            #expect(v.zoomed(by: 100, around: .zero).scale == 6)
            #expect(v.zoomed(by: 0.001, around: .zero).scale == 0.15)
        }

        @Test func panMovesTheOffsetOnly() {
            let v = BrainGraphViewport(scale: 2, offset: CGPoint(x: 1, y: 2), isAutomatic: false)
            let p = v.panned(by: CGSize(width: 10, height: -4))
            #expect(p.offset == CGPoint(x: 11, y: -2))
            #expect(p.scale == 2)
        }

        @Test func centringPutsTheWorldPointInTheMiddleAtTheSameScale() {
            let v = BrainGraphViewport(scale: 1.5, offset: CGPoint(x: 3, y: 4), isAutomatic: true)
            let c = v.centred(on: CGPoint(x: 40, y: -10), in: CGSize(width: 400, height: 600))
            #expect(c.screen(CGPoint(x: 40, y: -10)) == CGPoint(x: 200, y: 300))
            #expect(c.scale == 1.5)
            #expect(c.isAutomatic == false)
        }

        @Test func visibleWorldRectIsTheCanvasInWorldUnits() {
            let v = BrainGraphViewport(scale: 2, offset: CGPoint(x: 100, y: 100), isAutomatic: false)
            let r = v.visibleWorldRect(in: CGSize(width: 400, height: 200))
            #expect(r == CGRect(x: -50, y: -50, width: 200, height: 100))
        }
    }
}

// MARK: - Fit and the automatic view

extension BrainGraphCanvasLogicTests {
    struct BrainGraphFitTests {
        @Test func fitZoomCapLetsASmallGraphZoomTo2Point2AndCapsAnythingLargerAt1() {
            #expect(BrainGraphCanvasLogic.smallGraph == 80)
            #expect(BrainGraphCanvasLogic.fitZoomCap(pointCount: 80) == 2.2)
            #expect(BrainGraphCanvasLogic.fitZoomCap(pointCount: 25) == 2.2)
            #expect(BrainGraphCanvasLogic.fitZoomCap(pointCount: 81) == 1)
            #expect(BrainGraphCanvasLogic.fitZoomCap(pointCount: 1000) == 1)
        }

        private let bounds = CGRect(x: -50, y: -25, width: 100, height: 50)

        @Test func fitFillsTheCanvasInsideA12PercentMarginUpToTheCap() {
            // 1000x600: margin 72 pt, so 856x456 is available for 124x74 world units.
            let size = CGSize(width: 1000, height: 600)
            let t = BrainGraphViewport.fit(bounds: bounds, in: size, cap: 2.2)
            #expect(t.scale == 2.2)
            let tight = BrainGraphViewport.fit(bounds: bounds, in: size, cap: 10)
            #expect(abs(tight.scale - 456.0 / 74.0) < 1e-9)
            #expect(t.isAutomatic)
        }

        @Test func fitCentresTheBounds() {
            let t = BrainGraphViewport.fit(
                bounds: CGRect(x: 0, y: 0, width: 100, height: 40), in: CGSize(width: 1000, height: 600), cap: 1
            )
            #expect(abs(t.offset.x + 50 * t.scale - 500) < 1e-9)
            #expect(abs(t.offset.y + 20 * t.scale - 300) < 1e-9)
        }

        @Test func fitNeverZoomsOutPastTheMinimum() {
            let huge = CGRect(x: -1e5, y: -1e5, width: 2e5, height: 2e5)
            #expect(BrainGraphViewport.fit(bounds: huge, in: CGSize(width: 1000, height: 600), cap: 1).scale == 0.15)
        }

        @Test func boundsSkipNonFinitePoints() {
            let b = BrainGraphCanvasLogic.bounds(of: [
                CGPoint(x: 1, y: 2), CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: -3, y: 8), CGPoint(x: CGFloat.infinity, y: 1),
            ])
            #expect(b == CGRect(x: -3, y: 2, width: 4, height: 6))
            #expect(BrainGraphCanvasLogic.bounds(of: []) == nil)
            #expect(BrainGraphCanvasLogic.bounds(of: [CGPoint(x: CGFloat.nan, y: CGFloat.nan)]) == nil)
        }

        @Test func nextAutoViewStartsTrueOnAFreshGraph() {
            #expect(BrainGraphCanvasLogic.nextAutoView(false, .freshGraph))
            #expect(BrainGraphCanvasLogic.nextAutoView(true, .freshGraph))
        }

        @Test func nextAutoViewTurnsFalseWhenTheUserMovesTheViewOrAsksToCentre() {
            #expect(!BrainGraphCanvasLogic.nextAutoView(true, .userZoom))
            #expect(!BrainGraphCanvasLogic.nextAutoView(true, .userPan))
            #expect(!BrainGraphCanvasLogic.nextAutoView(true, .centreOn))
        }

        @Test func nextAutoViewIsLeftAloneByDraggingAPoint() {
            #expect(BrainGraphCanvasLogic.nextAutoView(true, .pointDrag))
            #expect(!BrainGraphCanvasLogic.nextAutoView(false, .pointDrag))
        }

        @Test func nextAutoViewIsRestoredByAFreshGraphAfterTheUserMovedTheView() {
            let moved = BrainGraphCanvasLogic.nextAutoView(true, .userPan)
            #expect(BrainGraphCanvasLogic.nextAutoView(moved, .freshGraph))
        }

        @Test func resizeRefitsWhileAutomaticAndNeverUnderADraggedPoint() {
            #expect(BrainGraphCanvasLogic.resizeAction(autoView: true, dragging: false) == .refit)
            #expect(BrainGraphCanvasLogic.resizeAction(autoView: false, dragging: false) == .recentre)
            #expect(BrainGraphCanvasLogic.resizeAction(autoView: true, dragging: true) == .recentre)
        }

        private let t = BrainGraphViewport(scale: 1.5, offset: CGPoint(x: 120, y: -40), isAutomatic: false)

        @Test func recentreKeepsTheWorldPointUnderTheOldCentreUnderTheNewCentre() {
            let next = t.recentred(from: CGSize(width: 1200, height: 800), to: CGSize(width: 850, height: 800))
            let o = t.world(CGPoint(x: 600, y: 400))
            let n = next.world(CGPoint(x: 425, y: 400))
            #expect(abs(n.x - o.x) < 1e-9 && abs(n.y - o.y) < 1e-9)
            let taller = t.recentred(from: CGSize(width: 1200, height: 800), to: CGSize(width: 1200, height: 500))
            let h = taller.world(CGPoint(x: 600, y: 250))
            #expect(abs(h.x - o.x) < 1e-9 && abs(h.y - o.y) < 1e-9)
        }

        @Test func recentreLeavesTheScaleAloneAndRoundTrips() {
            let a = CGSize(width: 1200, height: 800), b = CGSize(width: 850, height: 800)
            #expect(t.recentred(from: a, to: CGSize(width: 850, height: 600)).scale == 1.5)
            #expect(t.recentred(from: a, to: b).recentred(from: b, to: a) == t)
            #expect(t.recentred(from: a, to: a) == t)
        }
    }
}

// MARK: - Hit testing

extension BrainGraphCanvasLogicTests {
    struct BrainGraphHitTestTests {
        private let points = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 200, y: 0)]
        private let radii: [CGFloat] = [4, 4, 12]
        private let ids = ["a", "b", "big"]

        private func hit(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) -> String? {
            BrainGraphCanvasLogic.hitTest(points: points, radii: radii, at: CGPoint(x: x, y: y), scale: scale)
                .map { ids[$0] }
        }

        @Test func picksTheNearestPointWithinTheHitRadius() {
            #expect(BrainGraphCanvasLogic.hitFloor == 22)
            #expect(hit(3, 0, 1) == "a")
            #expect(hit(9, 0, 1) == "a")
            #expect(hit(11, 0, 1) == "b")
            #expect(hit(16, 1, 1) == "b")
        }

        @Test func returnsNilOutsideTheHitRadius() {
            // At scale 1 the floor is 22 world units.
            #expect(hit(0, 22.5, 1) == nil)
            #expect(hit(100, 0, 1) == nil)
        }

        @Test func usesThePointRadiusWhenItIsLargerThanTheFloor() {
            // At scale 4 the floor is 5.5, but the big point is 12 across.
            #expect(hit(211, 0, 4) == "big")
            #expect(hit(5, 0, 4) == "a")
            #expect(hit(6, 0, 4) == nil)
        }

        @Test func enlargesTheHitRadiusWhenZoomedOut() {
            // At scale 0.2 the floor is 110 world units.
            #expect(hit(0, 30, 1) == nil)
            #expect(hit(0, 30, 0.2) == "a")
            #expect(hit(0, 109, 0.2) == "a")
            #expect(hit(0, 132, 0.2) == nil)
        }

        @Test func ignoresNonFinitePointsAndAnEmptyGraph() {
            #expect(BrainGraphCanvasLogic.hitTest(points: [], radii: [], at: .zero, scale: 1) == nil)
            let odd = [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 5, y: 0)]
            #expect(BrainGraphCanvasLogic.hitTest(points: odd, radii: [4, 4], at: .zero, scale: 1) == 1)
        }
    }
}

// MARK: - Labels

extension BrainGraphCanvasLogicTests {
    struct BrainGraphLabelRuleTests {
        @Test func topTenthWeightIsTheLightestWeightAmongTheHeaviestTenth() {
            #expect(BrainGraphCanvasLogic.topTenthWeight(Array(1 ... 20)) == 19)
        }

        @Test func topTenthWeightNeverLetsAWeightlessPointIn() {
            #expect(BrainGraphCanvasLogic.topTenthWeight([0, 0, 0]) == 1)
            #expect(BrainGraphCanvasLogic.topTenthWeight([]) == 1)
        }

        private func offer(_ weight: Int, _ zoom: CGFloat, small: Bool = false) -> Bool {
            BrainGraphCanvasLogic.offerLabel(lit: nil, weight: weight, zoom: zoom, topTenth: 20, small: small)
        }

        @Test func alwaysOffersALitPointAndOnlyLitPointsWhileSomethingIsLit() {
            #expect(BrainGraphCanvasLogic.offerLabel(lit: true, weight: 1, zoom: 0.2, topTenth: 20, small: false))
            #expect(!BrainGraphCanvasLogic.offerLabel(lit: false, weight: 99, zoom: 3, topTenth: 40, small: false))
        }

        @Test func offersEveryPointFromZoom1Point6() {
            #expect(offer(1, 1.6))
            #expect(!offer(1, 1.59))
        }

        @Test func offersEveryPointOfASmallGraphFromZoom0Point5() {
            #expect(offer(1, 0.5, small: true))
            #expect(offer(1, 1, small: true))
            #expect(!offer(1, 0.49, small: true))
            #expect(!offer(1, 1, small: false))
        }

        @Test func offersTheTopTenthByWeightFromZoom0Point9() {
            #expect(offer(30, 0.9))
            #expect(offer(20, 0.9))
            #expect(!offer(30, 0.89))
            #expect(!offer(1, 1.2))
        }

        @Test func labelsAvoidEveryPointOnlyInASmallGraph() {
            #expect(BrainGraphCanvasLogic.labelsAvoidEveryPoint(pointCount: 80))
            #expect(!BrainGraphCanvasLogic.labelsAvoidEveryPoint(pointCount: 81))
        }

        @Test func atMost160Labels() {
            #expect(BrainGraphCanvasLogic.maxLabels == 160)
        }

        @Test func truncateKeepsShortLabels() {
            #expect(BrainGraphCanvasLogic.truncateLabel("Go notes") == "Go notes")
            #expect(BrainGraphCanvasLogic.truncateLabel(String(repeating: "x", count: 28)) == String(repeating: "x", count: 28))
        }

        @Test func truncateCutsLongLabelsTo28CharactersWithAnEllipsis() {
            let out = BrainGraphCanvasLogic.truncateLabel("A rather long title for a note about graphs")
            #expect(out == "A rather long title for a no…")
            #expect(out.count == 29)
        }

        @Test func truncateTrimsTrailingSpaceBeforeTheEllipsis() {
            let out = BrainGraphCanvasLogic.truncateLabel("abcdefghijklmnopqrstuvwxyz1 3456")
            #expect(out == "abcdefghijklmnopqrstuvwxyz1…")
        }
    }
}

extension BrainGraphCanvasLogicTests {
    struct BrainGraphLabelPlacementTests {
        // A point at (100, 100) of screen radius 5, label 40 pt wide, 11 pt tall.
        private let text = CGSize(width: 40, height: 11)
        private var spots: BrainLabelSpots {
            BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 100, y: 100), radius: 5, text: text)
        }

        @Test func triesBelowThenAboveThenRightNeverTouchingThePoint() {
            let s = spots
            #expect(s.below.rect.minY > 105)
            #expect(s.above.rect.maxY < 95)
            #expect(s.right.rect.minX > 105)
            for spot in [s.below, s.above] {
                #expect(spot.rect.width == 44)
                #expect(spot.text.x == 100)
            }
            #expect(s.right.text.x == s.right.rect.midX)
            #expect(s.right.rect.minY < 100)
            #expect(s.right.rect.maxY > 100)
        }

        @Test func anchorsTheTextOnePointInsideTheTopOfEachBox() {
            let s = spots
            for spot in [s.below, s.above, s.right] {
                #expect(spot.text.y == spot.rect.minY + 1)
            }
        }

        private let canvas = CGSize(width: 800, height: 600)

        private func off(_ x: CGFloat, _ y: CGFloat) -> Bool {
            BrainGraphCanvasLogic.labelOffscreen(centre: CGPoint(x: x, y: y), radius: 5, text: text, canvas: canvas)
        }

        @Test func offscreenKeepsAPointOnTheCanvasAndOneJustOffWhoseLabelCouldShow() {
            #expect(!off(400, 300))
            #expect(!off(-20, 300))
            #expect(!off(400, 610))
        }

        @Test func offscreenRejectsAPointWhenEverySpotIsOffTheCanvas() {
            #expect(off(-100, 300))
            #expect(off(830, 300))
            #expect(off(400, -30))
            #expect(off(400, 640))
        }

        @Test func offscreenAgreesWithTheSpotsThemselves() {
            let bounds = CGRect(origin: .zero, size: canvas)
            for (x, y) in [(-60.0, 300.0), (-59, 300), (400, -22), (400, 627), (400, 617), (-61, 300)] {
                let s = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: x, y: y), radius: 5, text: text)
                let anyIn = [s.below, s.above, s.right].contains { $0.rect.intersects(bounds) }
                #expect(off(x, y) == !anyIn, "\(x),\(y)")
            }
        }

        @Test func placeTakesTheFirstFreeSide() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            #expect(boxes.place(spots, canvas: canvas, force: false) == spots.below)
        }

        @Test func placeMovesToTheNextSideWhenACircleCoversTheFirst() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            boxes.occupy(CGRect(x: 95, y: 108, width: 10, height: 10))
            #expect(boxes.place(spots, canvas: canvas, force: false) == spots.above)
            boxes.occupy(CGRect(x: 95, y: 82, width: 10, height: 10))
            #expect(boxes.place(spots, canvas: canvas, force: false) == spots.right)
        }

        @Test func placeSkipsTheLabelWhenEverySideIsCoveredUnlessForced() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            for s in [spots.below, spots.above, spots.right] { boxes.occupy(s.rect) }
            #expect(boxes.place(spots, canvas: canvas, force: false) == nil)
            #expect(boxes.place(spots, canvas: canvas, force: true) == spots.below)
        }

        @Test func aForcedLabelIsPlacedRegardlessAndStillBlocksLaterOnes() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            boxes.occupy(spots.below.rect)
            boxes.occupy(spots.above.rect)
            boxes.occupy(spots.right.rect)
            let forced = boxes.place(spots, canvas: canvas, force: true)
            #expect(forced == spots.below)
            // A later label over the same place finds nothing free.
            #expect(boxes.place(spots, canvas: canvas, force: false) == nil)
        }

        @Test func placeClaimsTheChosenBox() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            _ = boxes.place(spots, canvas: canvas, force: false)
            #expect(!boxes.isFree(spots.below.rect))
        }

        @Test func placeUsesOnlySpotsOnTheCanvas() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            // Point at the bottom edge: below is off the canvas, so above is first.
            let edge = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 400, y: 596), radius: 5, text: text)
            #expect(boxes.place(edge, canvas: canvas, force: true) == edge.above)
            // Entirely off: nothing, even when forced.
            let gone = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: -500, y: 300), radius: 5, text: text)
            #expect(boxes.place(gone, canvas: canvas, force: true) == nil)
        }

        @Test func placeSkipsASpotTheEdgeWouldCutUnlessForced() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            // Near the right edge: below and above run past it, right is off it.
            let edge = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 790, y: 300), radius: 5, text: text)
            #expect(boxes.place(edge, canvas: canvas, force: false) == nil)
            let forced = boxes.place(edge, canvas: canvas, force: true)
            #expect(forced == BrainGraphCanvasLogic.forcedSpot(edge, canvas: canvas))
        }

        @Test func aForcedLabelAtTheRightEdgeSlidesLeftOntoTheCanvas() {
            let edge = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 790, y: 300), radius: 5, text: text)
            let spot = BrainGraphCanvasLogic.forcedSpot(edge, canvas: canvas)
            #expect(spot.rect.maxX == canvas.width)
            #expect(spot.rect.minY == edge.below.rect.minY)
            #expect(spot.rect.size == edge.below.rect.size)
            // The text moves with its plate.
            #expect(spot.text.x - spot.rect.midX == edge.below.text.x - edge.below.rect.midX)
            #expect(spot.text.y == edge.below.text.y)
        }

        @Test func aForcedLabelAtTheLeftEdgeSlidesRight() {
            let edge = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 3, y: 300), radius: 5, text: text)
            #expect(BrainGraphCanvasLogic.forcedSpot(edge, canvas: canvas).rect.minX == 0)
        }

        @Test func aForcedLabelAtTheBottomFlipsAbove() {
            let edge = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 400, y: 595), radius: 5, text: text)
            let spot = BrainGraphCanvasLogic.forcedSpot(edge, canvas: canvas)
            #expect(spot == edge.above)
        }

        @Test func aForcedLabelInACornerStaysWhollyOnTheCanvas() {
            let corner = BrainGraphCanvasLogic.labelSpots(centre: CGPoint(x: 799, y: 599), radius: 5, text: text)
            let rect = BrainGraphCanvasLogic.forcedSpot(corner, canvas: canvas).rect
            #expect(CGRect(origin: .zero, size: canvas).contains(rect))
        }

        @Test func aForcedLabelWiderThanTheCanvasStartsAtTheLeftEdge() {
            let wide = BrainGraphCanvasLogic.labelSpots(
                centre: CGPoint(x: 400, y: 300), radius: 5, text: CGSize(width: 900, height: 11)
            )
            #expect(BrainGraphCanvasLogic.forcedSpot(wide, canvas: canvas).rect.minX == 0)
        }

        @Test func truncateToFitCutsByAverageCharacterWidthAndLeavesFittingLabels() {
            let label = String(repeating: "x", count: 20)
            #expect(BrainGraphCanvasLogic.truncateLabel(label, toFit: 200, measuredWidth: 100) == label)
            // 20 characters at 10 pt each into 100 pt: 9 characters and an ellipsis.
            let cut = BrainGraphCanvasLogic.truncateLabel(label, toFit: 100, measuredWidth: 200)
            #expect(cut == String(repeating: "x", count: 9) + "…")
        }

        @Test func boxesRefuseAnOverlapAcrossGridCells() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            let first = boxes.claim(CGRect(x: 50, y: 10, width: 100, height: 13))
            let overlapping = boxes.claim(CGRect(x: 140, y: 20, width: 60, height: 13))
            let besideIt = boxes.claim(CGRect(x: 150, y: 10, width: 50, height: 13))
            let belowIt = boxes.claim(CGRect(x: 50, y: 23, width: 100, height: 13))
            #expect(first)
            #expect(!overlapping)
            #expect(besideIt)
            #expect(belowIt)
        }

        @Test func boxesClearForgetsEverythingAndCanBeFilledAgain() {
            var boxes = BrainLabelBoxes(canvas: canvas)
            boxes.occupy(CGRect(x: 0, y: 0, width: 100, height: 20))
            #expect(!boxes.isFree(CGRect(x: 10, y: 5, width: 40, height: 10)))
            boxes.clear(canvas: canvas)
            #expect(boxes.isFree(CGRect(x: 10, y: 5, width: 40, height: 10)))
            boxes.occupy(CGRect(x: 200, y: 0, width: 100, height: 20))
            #expect(!boxes.isFree(CGRect(x: 250, y: 5, width: 10, height: 10)))
            #expect(boxes.isFree(CGRect(x: 10, y: 5, width: 40, height: 10)))
        }

        @Test func boxesOffTheCanvasStillCollide() {
            // Boxes past the edges fall into the border cells and are still compared exactly.
            var boxes = BrainLabelBoxes(canvas: canvas)
            boxes.occupy(CGRect(x: -80, y: -40, width: 50, height: 20))
            #expect(!boxes.isFree(CGRect(x: -60, y: -30, width: 10, height: 5)))
            #expect(boxes.isFree(CGRect(x: -20, y: -30, width: 10, height: 5)))
        }
    }
}

// MARK: - Presses

extension BrainGraphCanvasLogicTests {
    struct BrainPressTrackerTests {
        @Test func aStillPressIsATap() {
            var p = BrainPressTracker(start: CGPoint(x: 10, y: 10), hitID: "a")
            let phase = p.move(to: CGPoint(x: 13, y: 12))
            #expect(phase == .pending)
            #expect(p.allowsTap)
        }

        @Test func movingPastTheSlopOnAPointDragsItAndNeverTaps() {
            var p = BrainPressTracker(start: CGPoint(x: 10, y: 10), hitID: "a")
            let out = p.move(to: CGPoint(x: 10, y: 10 + BrainPressTracker.slop + 0.5))
            #expect(out == .draggingPoint)
            #expect(!p.allowsTap)
            // Coming back does not make it a tap again.
            let back = p.move(to: CGPoint(x: 10, y: 10))
            #expect(back == .draggingPoint)
            #expect(!p.allowsTap)
        }

        @Test func movingPastTheSlopOnEmptySpacePansAndNeverTaps() {
            var p = BrainPressTracker(start: .zero, hitID: nil)
            let phase = p.move(to: CGPoint(x: 9, y: 0))
            #expect(phase == .panning)
            #expect(!p.allowsTap)
        }

        @Test func aLongPressFiresOnceOnAPointThatHasNotMoved() {
            var p = BrainPressTracker(start: .zero, hitID: "a")
            let first = p.longPressElapsed()
            let second = p.longPressElapsed()
            #expect(first)
            #expect(!second)
            #expect(!p.allowsTap)
            // A long-pressed point can still be dragged afterwards.
            let phase = p.move(to: CGPoint(x: 20, y: 0))
            #expect(phase == .draggingPoint)
        }

        @Test func aLongPressDoesNotFireOnEmptySpaceOrAfterMoving() {
            var empty = BrainPressTracker(start: .zero, hitID: nil)
            let onEmpty = empty.longPressElapsed()
            #expect(!onEmpty)
            #expect(empty.allowsTap)
            var moved = BrainPressTracker(start: .zero, hitID: "a")
            _ = moved.move(to: CGPoint(x: 30, y: 0))
            let afterMoving = moved.longPressElapsed()
            #expect(!afterMoving)
        }

        @Test func aPinchEndsThePressAsNeitherTapNorPan() {
            var p = BrainPressTracker(start: .zero, hitID: nil)
            p.pinchBegan()
            let phase = p.move(to: CGPoint(x: 50, y: 0))
            #expect(phase == .pinching)
            #expect(!p.allowsTap)
            let long = p.longPressElapsed()
            #expect(!long)
        }

        // A cancelled drag never reaches `onEnded`: the next gesture's first
        // change finds the old press, with another start.

        @Test func noPressOrTheSameStartNeedsNoRecovery() {
            #expect(BrainPressTracker.recovery(current: nil, gestureStart: .zero) == .none)
            var p = BrainPressTracker(start: CGPoint(x: 10, y: 10), hitID: "a")
            _ = p.move(to: CGPoint(x: 40, y: 10))
            #expect(BrainPressTracker.recovery(current: p, gestureStart: CGPoint(x: 10, y: 10)) == .none)
        }

        @Test func aPressFromAnotherStartIsStaleAndRestarts() {
            let pending = BrainPressTracker(start: CGPoint(x: 10, y: 10), hitID: "a")
            #expect(BrainPressTracker.recovery(current: pending, gestureStart: CGPoint(x: 90, y: 10))
                == .restart(release: nil))
            var pinch = BrainPressTracker(start: .zero, hitID: nil)
            pinch.pinchBegan()
            #expect(BrainPressTracker.recovery(current: pinch, gestureStart: CGPoint(x: 5, y: 5))
                == .restart(release: nil))
            var pan = BrainPressTracker(start: .zero, hitID: nil)
            _ = pan.move(to: CGPoint(x: 50, y: 0))
            #expect(BrainPressTracker.recovery(current: pan, gestureStart: CGPoint(x: 5, y: 5))
                == .restart(release: nil))
        }

        @Test func aCancelledPointDragReleasesItsPin() {
            var p = BrainPressTracker(start: .zero, hitID: "a")
            _ = p.move(to: CGPoint(x: 50, y: 0))
            #expect(p.phase == .draggingPoint)
            #expect(BrainPressTracker.recovery(current: p, gestureStart: CGPoint(x: 200, y: 200))
                == .restart(release: "a"))
        }
    }
}

// MARK: - Motion

extension BrainGraphCanvasLogicTests {
    struct BrainViewportMotionTests {
        private let start = Date(timeIntervalSinceReferenceDate: 1000)
        private let from = BrainGraphViewport(scale: 1, offset: .zero, isAutomatic: false)

        @Test func easeRunsFromStartToEnd() {
            let to = BrainGraphViewport(scale: 2, offset: CGPoint(x: 100, y: -50), isAutomatic: true)
            let m = BrainViewportMotion.ease(from: from, to: to, start: start)
            // The motion starts where the view was; it is the automatic view
            // throughout, because that is where it is going.
            let first = m.viewport(at: start)
            #expect(first.scale == from.scale && first.offset == from.offset)
            #expect(first.isAutomatic == to.isAutomatic)
            #expect(m.viewport(at: start.addingTimeInterval(m.duration)) == to)
            let mid = m.viewport(at: start.addingTimeInterval(m.duration / 2))
            #expect(abs(mid.scale - 1.5) < 1e-9)
            #expect(m.end == to)
            #expect(m.duration == BrainViewportMotion.easeDuration)
        }

        @Test func aSlowReleaseDoesNotFling() {
            #expect(BrainViewportMotion.fling(from: from, velocity: CGSize(width: 30, height: 20), start: start) == nil)
        }

        @Test func aFlingDeceleratesTowardsItsRestingPlaceAndStops() throws {
            let m = try #require(BrainViewportMotion.fling(from: from, velocity: CGSize(width: 1000, height: 0), start: start))
            let early = m.viewport(at: start.addingTimeInterval(0.05)).offset.x
            let later = m.viewport(at: start.addingTimeInterval(0.3)).offset.x
            let end = m.viewport(at: start.addingTimeInterval(m.duration)).offset.x
            #expect(early > 0 && later > early && end > later)
            // Slowing down: the second 50 ms covers less than the first.
            let second = m.viewport(at: start.addingTimeInterval(0.1)).offset.x - early
            #expect(second < early)
            #expect(abs(end - m.end.offset.x) < 0.5)
            #expect(m.end.offset.x == 1000 * BrainViewportMotion.flingTimeConstant)
            #expect(m.duration < 3)
            #expect(!m.end.isAutomatic)
        }

        @Test func aFlingIsCappedSoItFeelsWeighty() throws {
            let m = try #require(BrainViewportMotion.fling(from: from, velocity: CGSize(width: 90000, height: 0), start: start))
            #expect(m.end.offset.x == BrainViewportMotion.maxFlingSpeed * BrainViewportMotion.flingTimeConstant)
        }

        @Test func beforeTheStartAMotionIsAtItsBeginning() throws {
            let m = try #require(BrainViewportMotion.fling(from: from, velocity: CGSize(width: 500, height: 500), start: start))
            #expect(m.viewport(at: start.addingTimeInterval(-1)) == from)
        }
    }
}

// MARK: - The automatic view of a set of points

extension BrainGraphCanvasLogicTests {
    struct BrainGraphFittedViewTests {
        @Test func fitsThePointsWithTheCapOfTheirCount() {
            let points = [CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0)]
            let size = CGSize(width: 400, height: 400)
            let v = BrainGraphCanvasLogic.fittedView(points: points, size: size)
            let expected = BrainGraphViewport.fit(
                bounds: CGRect(x: -10, y: 0, width: 20, height: 0), in: size, cap: 2.2
            )
            #expect(v == expected)
        }

        @Test func withNothingToFitTheOriginSitsInTheMiddleAtScale1() {
            let v = BrainGraphCanvasLogic.fittedView(points: [CGPoint(x: CGFloat.nan, y: 0)], size: CGSize(width: 300, height: 200))
            #expect(v == BrainGraphViewport(scale: 1, offset: CGPoint(x: 150, y: 100), isAutomatic: true))
        }
    }
}

extension BrainGraphCanvasLogicTests {
    struct BrainGraphMotionEndTests {
        @Test func aMotionIsFinishedOnceItsDurationHasPassed() {
            let start = Date(timeIntervalSinceReferenceDate: 0)
            let v = BrainGraphViewport(scale: 1, offset: .zero, isAutomatic: true)
            let m = BrainViewportMotion.ease(from: v, to: v.zoomed(by: 2, around: .zero), start: start)
            #expect(!m.isFinished(at: start.addingTimeInterval(m.duration / 2)))
            #expect(m.isFinished(at: start.addingTimeInterval(m.duration)))
        }
    }
}

// MARK: - Accessibility

extension BrainGraphCanvasLogicTests {
    struct BrainGraphCanvasAccessibilityTests {
        @Test func theCanvasIsOneElementNamingTheItemCountAndPointingToTheList() {
            #expect(
                BrainGraphCanvasLogic.accessibilityLabel(itemCount: 42)
                    == "Graph of 42 notes and memories. Use the list to browse."
            )
        }
    }
}

// MARK: - Scene

extension BrainGraphCanvasLogicTests {
    @MainActor
    struct BrainCanvasSceneTests {
        private static let vault = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xAA))

        private static func item(_ id: String, weight: Int, kind: BrainNodeKindDTO = .note, label: String? = nil) -> BrainGraphNodeDTO {
            BrainGraphNodeDTO(id: id, kind: kind, label: label ?? id, vaultID: vault, weight: weight)
        }

        private static func graph(_ nodes: [BrainGraphNodeDTO], _ edges: [BrainGraphEdgeDTO]) -> VisibleBrainGraph {
            var index = BrainGraphIndex()
            for n in nodes { index.byID[n.id] = n }
            return VisibleBrainGraph(nodes: nodes, edges: edges, index: index)
        }

        private let graph = Self.graph(
            [
                item("a", weight: 1),
                item("b", weight: 5, kind: .memory),
                item("tag:go", weight: 3, kind: .tag, label: "go"),
                item("c", weight: 2, label: "A rather long title for a note about graphs"),
            ],
            [
                BrainGraphEdgeDTO(from: "a", to: "tag:go", kind: .tag),
                BrainGraphEdgeDTO(from: "b", to: "tag:go", kind: .tag),
                BrainGraphEdgeDTO(from: "a", to: "a", kind: .link),
                BrainGraphEdgeDTO(from: "a", to: "gone", kind: .link),
                BrainGraphEdgeDTO(from: "c", to: "b", kind: .similar),
            ]
        )

        private func colour(_ node: BrainGraphNodeDTO) -> Color {
            node.kind == .memory ? .red : .blue
        }

        @Test func keepsTheGraphOrderWithRadiiHubsAndTruncatedText() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            #expect(s.ids == ["a", "b", "tag:go", "c"])
            #expect(s.index["tag:go"] == 2)
            #expect(s.isHub == [false, false, true, false])
            #expect(s.radius[1] == ForceSimulation2D.nodeRadius(weight: 5, isHub: false))
            #expect(s.radius[2] == ForceSimulation2D.nodeRadius(weight: 3, isHub: true))
            #expect(s.text[3] == "A rather long title for a no…")
            #expect(s.itemCount == 3)
        }

        @Test func dropsSelfEdgesAndEdgesToPointsItDoesNotHave() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            let expected: [BrainCanvasScene.Edge] = [
                BrainCanvasScene.Edge(a: 0, b: 2, kind: .tag),
                BrainCanvasScene.Edge(a: 1, b: 2, kind: .tag),
                BrainCanvasScene.Edge(a: 3, b: 1, kind: .similar),
            ]
            #expect(s.edges == expected)
        }

        @Test func ordersByWeightHeaviestFirstAndKnowsTheTopTenth() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            #expect(s.byWeight == [1, 2, 3, 0])
            #expect(s.topTenth == 5)
        }

        @Test func groupsItemsByColourAndKeepsHubsApart() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            let members: [[Int]] = s.fills.map(\.members)
            let colours: [Color] = s.fills.map(\.colour)
            #expect(members == [[0, 3], [1]])
            #expect(colours == [Color.blue, Color.red])
            #expect(s.hubs == [2])
        }

        @Test func theLayoutKeyChangesWithThePointsAndEdgesButNotTheColours() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            #expect(BrainCanvasScene(graph: graph, colourOf: { _ in Color.green }).layoutKey == s.layoutKey)
            let fewer = Self.graph(Array(graph.nodes.dropLast()), graph.edges)
            #expect(BrainCanvasScene(graph: fewer, colourOf: colour).layoutKey != s.layoutKey)
            let moreEdges = Self.graph(graph.nodes, graph.edges + [BrainGraphEdgeDTO(from: "a", to: "c", kind: .link)])
            #expect(BrainCanvasScene(graph: moreEdges, colourOf: colour).layoutKey != s.layoutKey)
        }

        @Test func alignsASnapshotToTheSceneByIDLeavingUnknownPointsUnplaced() {
            let s = BrainCanvasScene(graph: graph, colourOf: colour)
            let snapshot = LayoutSnapshot(
                ids: ["a", "b", "c", "zzz"],
                points: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3), CGPoint(x: 9, y: 9)],
                settled: true,
                generation: 1
            )
            let p = s.aligned(snapshot)
            #expect(p.count == 4)
            #expect(p[0] == CGPoint(x: 1, y: 1))
            #expect(p[1] == CGPoint(x: 2, y: 2))
            #expect(p[2].x.isNaN)
            #expect(p[3] == CGPoint(x: 3, y: 3))
        }

        @Test func aGraphIsFreshOnlyWhenNoneOfItsIDsWasSeenBefore() {
            #expect(BrainGraphCanvasLogic.isFreshGraph(["a", "b"], known: []))
            #expect(!BrainGraphCanvasLogic.isFreshGraph(["a", "b"], known: ["b"]))
            #expect(!BrainGraphCanvasLogic.isFreshGraph([], known: []))
        }
    }
}
