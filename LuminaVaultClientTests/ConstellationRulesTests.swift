// The Constellation's pure rules: ports of the web app's render-3d.test.ts
// cases that have an iOS counterpart, plus the iOS-only rules (the 22 pt hit
// floor, the 800-star cap, the camera, the generated meshes).
//
// Not ported, because iOS has nothing they test: parseColour and
// isLightBackground (colours come from the palette as Colors), growCapacity
// and pointSizeLimits (WebGL buffers and point sprites), depthOrder (stars are
// opaque, nothing is sorted), starPixelSize (spheres scale with distance),
// projectPoints and viewPlanePosition (the camera projects itself; see
// ConstellationCameraTests), controlsChangeEvent (OrbitControls), and
// placeClear / spotsInView (labels are placed by the 2D canvas's tested
// `BrainLabelBoxes.place`, whose forced spot slides a selected label on screen).

import CoreGraphics
import Foundation
import simd
import SwiftUI
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

nonisolated private func projection(
    _ points: [(CGFloat, CGFloat, CGFloat)], radii: [CGFloat], size: CGSize = CGSize(width: 100, height: 100)
) -> ConstellationProjection {
    ConstellationProjection(
        x: points.map(\.0), y: points.map(\.1), depth: points.map(\.2), radius: radii, size: size
    )
}

struct ConstellationPickTests {
    private let screen = projection(
        [(10, 10, 5), (100, 100, 5), (104, 100, 2), (.nan, 0, 0)], radii: [2, 30, 2, 2], size: CGSize(width: 400, height: 400)
    )

    @Test func picksAStarWithinMaxRadiusFloor() {
        #expect(ConstellationRules.pickStar(screen, at: CGPoint(x: 12, y: 12), floor: 12) == 0)
        // The big star reaches 30.
        #expect(ConstellationRules.pickStar(screen, at: CGPoint(x: 125, y: 100), floor: 12) == 1)
    }

    @Test func missesBeyondTheFloorAndIgnoresPointsBehindTheCamera() {
        #expect(ConstellationRules.pickStar(screen, at: CGPoint(x: 40, y: 40), floor: 12) == nil)
        #expect(ConstellationRules.pickStar(screen, at: CGPoint(x: CGFloat.nan, y: 0), floor: 12) == nil)
        let first = projection([(10, 10, 5)], radii: [2])
        #expect(ConstellationRules.pickStar(first, at: CGPoint(x: 100, y: 100), floor: 12) == nil)
    }

    @Test func prefersALargeNearStarToATinyFarOneAPointCloser() {
        let s = projection([(200, 200, 20), (193, 200, 400)], radii: [30, 1])
        #expect(ConstellationRules.pickStar(s, at: CGPoint(x: 196, y: 200), floor: 12) == 0)
        // Right on top of the tiny star, it wins.
        #expect(ConstellationRules.pickStar(s, at: CGPoint(x: 193, y: 200), floor: 12) == 1)
    }

    @Test func breaksATieOnDepthTheNearerStarWins() {
        let s = projection([(50, 50, 300), (50, 50, 40)], radii: [5, 5])
        #expect(ConstellationRules.pickStar(s, at: CGPoint(x: 52, y: 50), floor: 12) == 1)
    }

    @Test func stillPrefersTheCloserOfTwoStarsTheSameSize() {
        #expect(ConstellationRules.pickStar(screen, at: CGPoint(x: 103, y: 100), floor: 12) == 2)
    }

    @Test func aFingertipReaches22PointsByDefault() {
        let s = projection([(50, 50, 10)], radii: [2])
        #expect(ConstellationRules.pickStar(s, at: CGPoint(x: 71, y: 50)) == 0)
        #expect(ConstellationRules.pickStar(s, at: CGPoint(x: 73, y: 50)) == nil)
    }
}

struct ConstellationLabelRankTests {
    @Test func ordersSelectedThenLitThenTheRestSkippingHiddenAndOffscreen() {
        let p = projection(
            [(10, 10, 9), (20, 20, 1), (30, 30, 5), (40, 40, 2), (-50, 40, 1), (60, 60, 3), (.nan, 0, 0)],
            radii: Array(repeating: 1, count: 7)
        )
        let tiers: [ConstellationTier] = [.other, .other, .selected, .lit, .selected, .hidden, .lit]
        #expect(ConstellationRules.rankLabels(p, tiers: tiers, weights: Array(repeating: 0, count: 7)) == [2, 3, 1, 0])
    }

    @Test func ranksTheRestingTierByWeightNearnessBreakingTies() {
        let p = projection([(10, 10, 1), (20, 20, 9), (30, 30, 5), (40, 40, 2)], radii: [1, 1, 1, 1])
        let tiers: [ConstellationTier] = [.other, .other, .other, .lit]
        // Lit first whatever its weight; then 2 and 1 (weight 8, 2 nearer), then 0.
        #expect(ConstellationRules.rankLabels(p, tiers: tiers, weights: [1, 8, 8, 0]) == [3, 2, 1, 0])
    }

    @Test func givesAPhoneSizedViewFewerLabelsThanADesktopOne() {
        #expect(ConstellationRules.labelQuota(CGSize(width: 1136, height: 776)) == 24)
        #expect(ConstellationRules.labelQuota(CGSize(width: 358, height: 650)) < 24)
        #expect(ConstellationRules.labelQuota(CGSize(width: 100, height: 100)) == 8)
    }

    @Test func placesAtMostTheQuotaKeepsSelectedLabelsAndCoversNoSelectionRing() {
        // A crowded 300 x 300 view: 200 stars on a grid, two selected.
        var points: [(CGFloat, CGFloat, CGFloat)] = []
        for i in 0 ..< 200 { points.append((CGFloat(i % 20) * 15 + 7, CGFloat(i / 20) * 30 + 10, 100)) }
        let size = CGSize(width: 300, height: 300)
        let p = projection(points, radii: Array(repeating: 3, count: 200), size: size)
        var tiers = [ConstellationTier](repeating: .other, count: 200)
        tiers[45] = .selected
        tiers[150] = .selected
        let labels = ConstellationRules.placeLabels(
            p, tiers: tiers, weights: (0 ..< 200).map(Double.init), texts: (0 ..< 200).map { "Note \($0)" }
        ) { CGSize(width: CGFloat($0.count) * 6, height: 14) }
        #expect(labels.count <= ConstellationRules.labelQuota(size))
        #expect(labels.contains { $0.star == 45 && $0.selected })
        #expect(labels.contains { $0.star == 150 && $0.selected })
        let bounds = CGRect(origin: .zero, size: size)
        for label in labels {
            #expect(bounds.contains(label.rect))
            for ring in [45, 150] {
                let r = ConstellationRules.ringRadius
                let box = CGRect(x: p.x[ring] - r, y: p.y[ring] - r, width: r * 2, height: r * 2)
                #expect(!label.rect.intersects(box))
            }
        }
        for (i, a) in labels.enumerated() {
            for b in labels[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) }
        }
    }

    @Test func aCloseUpSelectedStarsLabelClearsItsWholeRing() {
        let p = projection([(200, 200, 70), (300, 300, 70)], radii: [40, 4], size: CGSize(width: 400, height: 400))
        let labels = ConstellationRules.placeLabels(
            p, tiers: [.selected, .other], weights: [1, 1], texts: ["Garden plans", "home"]
        ) { CGSize(width: CGFloat($0.count) * 6, height: 14) }
        let reach = ConstellationRules.selectionReach(40)
        #expect(reach == 56)
        let ring = CGRect(x: 200 - reach, y: 200 - reach, width: reach * 2, height: reach * 2)
        let garden = labels.first { $0.star == 0 }
        #expect(garden != nil)
        #expect(garden.map { !$0.rect.intersects(ring) } ?? false)
        let home = labels.first { $0.star == 1 }
        let star = CGRect(x: 296, y: 296, width: 8, height: 8)
        #expect(home.map { !$0.rect.intersects(star) } ?? false)
    }

    @Test func neverMoreThan24() {
        let size = CGSize(width: 2000, height: 2000)
        var points: [(CGFloat, CGFloat, CGFloat)] = []
        for i in 0 ..< 400 {
            let x = CGFloat(i % 20) * 100 + 20
            let y = CGFloat(i / 20) * 100 + 20
            points.append((x, y, 10))
        }
        let p = projection(points, radii: Array(repeating: 2, count: 400), size: size)
        let labels = ConstellationRules.placeLabels(
            p, tiers: Array(repeating: .other, count: 400), weights: Array(repeating: 1, count: 400),
            texts: Array(repeating: "x", count: 400)
        ) { _ in CGSize(width: 8, height: 14) }
        #expect(labels.count == 24)
    }
}

struct ConstellationEdgeTests {
    private let edges = [(0, 1), (1, 2), (2, 3), (0, 3)].map {
        ConstellationModel.Edge(a: $0.0, b: $0.1, kind: .link)
    }

    @Test func drawsTheRestingEdgesWhenNothingIsLit() {
        let pick = ConstellationRules.constellationEdges(edges, rest: [3, 0], lit: nil, seed: nil)
        #expect(pick.indices == [3, 0])
        #expect(!pick.lit)
    }

    @Test func drawsOnlyTheEdgesOfASeedInsideTheLitSetWhileSomethingIsLit() {
        let pick = ConstellationRules.constellationEdges(
            edges, rest: [3, 0], lit: [true, true, false, true], seed: [true, false, false, false]
        )
        #expect(pick.indices == [0, 3])
        #expect(pick.lit)
    }

    @Test func keepsTheHighestScoringEligibleEdgesBestFirstUpToTheLimit() {
        #expect(ConstellationRules.restingEdges(
            eligible: [true, false, true, true, true], scores: [2, 99, 5, 5, 1], limit: 3
        ) == [2, 3, 0])
    }

    @Test func defaultsTo300() {
        #expect(ConstellationRules.restEdgeLimit == 300)
        #expect(ConstellationRules.restingEdges(
            eligible: Array(repeating: true, count: 500), scores: Array(repeating: 0, count: 500)
        ).count == 300)
    }
}

struct ConstellationModelTests {
    private static func node(_ id: String, _ kind: BrainNodeKindDTO, weight: Int) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: kind, label: id, weight: weight)
    }

    private static func graph(_ nodes: [BrainGraphNodeDTO], _ edges: [BrainGraphEdgeDTO]) -> VisibleBrainGraph {
        let raw = BrainGraphResponse(generatedAt: Date(timeIntervalSince1970: 0), vaults: [], nodes: nodes, edges: edges)
        return BrainGraphModel.visible(raw, filters: BrainGraphModel.defaultFilters())
    }

    /// a-b link, b-c link, a-c source, a and b tagged t.
    private static let small = graph(
        [node("a", .note, weight: 9), node("b", .note, weight: 3), node("c", .memory, weight: 1), node("t", .tag, weight: 2)],
        [
            BrainGraphEdgeDTO(from: "a", to: "b", kind: .link),
            BrainGraphEdgeDTO(from: "b", to: "c", kind: .link),
            BrainGraphEdgeDTO(from: "a", to: "c", kind: .source),
            BrainGraphEdgeDTO(from: "a", to: "t", kind: .tag),
            BrainGraphEdgeDTO(from: "b", to: "t", kind: .tag),
        ]
    )

    @Test func restsOnTheStrongestLinkAndSimilarEdgesOnly() {
        let m = ConstellationModel(graph: Self.small) { _ in .clear }
        let rest = m.rest.map { m.edges[$0] }
        #expect(rest.allSatisfy { $0.kind == .link })
        // a-b (9 + 3) before b-c (3 + 1).
        #expect(rest.map { [m.ids[$0.a], m.ids[$0.b]] } == [["a", "b"], ["b", "c"]])
    }

    @Test func selectingLightsTheNeighbourhoodDimsTheRestAndDrawsTheSeedsEdges() {
        let m = ConstellationModel(graph: Self.small) { _ in .clear }
        let highlight = BrainHighlight(selected: ["c"], lit: BrainGraphModel.litSet(Self.small.index, ids: ["c"]))
        let look = ConstellationRules.look(m, highlight: highlight)
        let tier = { (id: String) in look.tiers[m.index[id] ?? -1] }
        #expect(tier("c") == .selected)
        #expect(tier("a") == .lit)
        #expect(tier("b") == .lit)
        #expect(tier("t") == .hidden)
        #expect(look.isDimmed(m.index["t"] ?? -1))
        #expect(look.linesLit)
        let drawn = Set(look.lines.map { [m.ids[m.edges[$0].a], m.ids[m.edges[$0].b]].sorted() })
        #expect(drawn == [["a", "c"], ["b", "c"]])
    }

    @Test func nothingSelectedDimsNothingAndRests() {
        let m = ConstellationModel(graph: Self.small) { _ in .clear }
        let look = ConstellationRules.look(m, highlight: BrainHighlight(selected: [], lit: nil))
        #expect(look.tiers.allSatisfy { $0 == .other })
        #expect(look.lines == m.rest)
        #expect(!look.linesLit)
    }

    @Test func dimmedStarsKeep15PercentOfTheirColour() {
        #expect(ConstellationRules.dimIntensity == 0.15)
    }

    @Test func drawsAtMost800StarsTheHeaviestInGraphOrder() {
        let nodes: [BrainGraphNodeDTO] = (0 ..< 900).map { i in Self.node("n\(i)", .note, weight: i % 10) }
        let kept = ConstellationRules.keptNodes(nodes)
        #expect(kept.count == 800)
        let keptIDs: [String] = kept.map { $0.id }
        let keptSet = Set(keptIDs)
        let inGraphOrder: [String] = nodes.filter { keptSet.contains($0.id) }.map { $0.id }
        #expect(keptIDs == inGraphOrder)
        // The 100 dropped are the lightest: weight 0 (90 of them) and ten of weight 1.
        let dropped: [BrainGraphNodeDTO] = nodes.filter { !keptSet.contains($0.id) }
        #expect(dropped.count == 100)
        #expect(dropped.allSatisfy { $0.weight <= 1 })
        #expect(ConstellationRules.keptNodes(Array(nodes.prefix(10))).count == 10)
    }

    @Test func heavierStarsAreLargerHubsStayQuietAndSmallGraphsAreBoosted() {
        let light = ConstellationRules.starRadius(weight: 0, isHub: false, boost: 1)
        let heavy = ConstellationRules.starRadius(weight: 64, isHub: false, boost: 1)
        #expect(heavy > light)
        #expect(ConstellationRules.starRadius(weight: 1000, isHub: true, boost: 1.7) <= ConstellationRules.maxHubRadius)
        #expect(ConstellationRules.smallGraphBoost(25) == ConstellationRules.smallBoost)
        #expect(ConstellationRules.smallGraphBoost(300) == 1)
        #expect(ConstellationRules.smallGraphBoost(800) == 1)
    }

    @Test func itsKeysTellDrawingChangesFromLayoutChanges() {
        let a = ConstellationModel(graph: Self.small) { _ in .clear }
        let b = ConstellationModel(graph: Self.small) { _ in .red }
        #expect(a.layoutKey == b.layoutKey)
        #expect(a.key != b.key)
        #expect(a.itemCount == 3)
    }
}

struct ConstellationScreenSizeTests {
    // Web `starPixelSize`.
    @Test func shrinksWithDistanceButNeverBelowTheFloorOrAboveTheCeiling() {
        #expect(abs(ConstellationRules.starPixelSize(10, depth: 100, pointsPerUnit: 500, min: 3, max: 64) - 50) < 1e-9)
        #expect(abs(ConstellationRules.starPixelSize(10, depth: 200, pointsPerUnit: 500, min: 3, max: 64) - 25) < 1e-9)
        #expect(ConstellationRules.starPixelSize(10, depth: 1e6, pointsPerUnit: 500, min: 3, max: 64) == 3)
        #expect(ConstellationRules.starPixelSize(10, depth: 1, pointsPerUnit: 500, min: 3, max: 64) == 64)
        #expect(ConstellationRules.starPixelSize(10, depth: 0, pointsPerUnit: 500, min: 3, max: 64) == 64)
    }

    @Test func aStarsRadiusIsItsSpriteClampedToTheWebsBoundsThenBackToTheCore() {
        let core = ConstellationRules.coreShare
        // Unclamped: world radius over depth, times points per unit.
        let mid = ConstellationRules.screenRadius(worldRadius: 2, isHub: false, depth: 100, pointsPerUnit: 700)
        #expect(abs(mid - 14) < 1e-6)
        // Close up: never past the 58 pt sprite.
        let near = ConstellationRules.screenRadius(worldRadius: 2, isHub: false, depth: 3, pointsPerUnit: 700)
        #expect(abs(near - ConstellationRules.maxStarPoints * core) < 1e-6)
        // Far away: never under the 5 pt sprite.
        let far = ConstellationRules.screenRadius(worldRadius: 2, isHub: false, depth: 1e5, pointsPerUnit: 700)
        #expect(abs(far - ConstellationRules.minStarPoints * core) < 1e-6)
        // A hub stays a small mark: 15 pt at most.
        let hub = ConstellationRules.screenRadius(worldRadius: 2, isHub: true, depth: 3, pointsPerUnit: 700)
        #expect(abs(hub - ConstellationRules.maxHubPoints * ConstellationRules.hubShare) < 1e-6)
    }

    @Test func theProjectionCarriesTheClampedRadiusSoATapHitsWhatIsDrawn() {
        let raw = projection([(200, 200, 3), (100, 100, .nan)], radii: [466, 0], size: CGSize(width: 400, height: 400))
        let p = ConstellationRules.clampedRadii(raw, worldRadii: [2, 2], isHub: [false, false], pointsPerUnit: 700)
        let top = ConstellationRules.maxStarPoints * ConstellationRules.coreShare
        #expect(abs(p.radius[0] - top) < 1e-6)
        #expect(p.radius[1] == 0)
        // 30 pt away was inside the unclamped 466 pt disc; it is outside the
        // drawn 18 pt one and the 22 pt fingertip.
        #expect(ConstellationRules.pickStar(raw, at: CGPoint(x: 230, y: 200)) == 0)
        #expect(ConstellationRules.pickStar(p, at: CGPoint(x: 230, y: 200)) == nil)
        #expect(ConstellationRules.pickStar(p, at: CGPoint(x: 220, y: 200)) == 0)
    }

    @Test func aStarIsScaledSoItIsDrawnAtItsClampedRadius() {
        let k: CGFloat = 700
        let r = ConstellationRules.screenRadius(worldRadius: 2, isHub: false, depth: 3, pointsPerUnit: k)
        let scale = ConstellationRules.drawnScale(radius: r, depth: 3, pointsPerUnit: k)
        #expect(abs(CGFloat(scale) * k / 3 - r) < 1e-4)
        // Unclamped, the scale is the world radius.
        let free = ConstellationRules.screenRadius(worldRadius: 2, isHub: false, depth: 100, pointsPerUnit: k)
        #expect(abs(ConstellationRules.drawnScale(radius: free, depth: 100, pointsPerUnit: k) - 2) < 1e-5)
    }

    @Test func aLineIsOnePointWideAtAnyDepth() {
        let k: Float = 700
        for depth: Float in [20, 300, 1500] {
            let w = ConstellationRules.lineWorldWidth(depth: depth, pointsPerUnit: k)
            #expect(abs(w * k / depth - ConstellationRules.lineScreenWidth) < 1e-5)
        }
        // Behind or at the eye: the near plane's width, not zero or negative.
        #expect(ConstellationRules.lineWorldWidth(depth: -5, pointsPerUnit: k) > 0)
    }

    @Test func linesAreRebuiltOnceTheCameraHasMovedFarEnough() {
        #expect(ConstellationRules.linesNeedRebuild(builtEye: nil, eye: .zero, distance: 300))
        #expect(!ConstellationRules.linesNeedRebuild(builtEye: [0, 0, 300], eye: [0, 0, 290], distance: 300))
        #expect(ConstellationRules.linesNeedRebuild(builtEye: [0, 0, 300], eye: [0, 0, 150], distance: 150))
        #expect(ConstellationRules.linesNeedRebuild(builtEye: [0, 0, 300], eye: [100, 0, 280], distance: 300))
    }

    @Test func endsOfOneLineGetTheirOwnWidths() {
        let g = ConstellationMeshes.lines([.init(a: [0, 0, 0], b: [10, 0, 0], slot: 0)]) { end in end.x == 0 ? 1 : 3 }
        #expect(abs(simd_distance(g.positions[0], g.positions[1]) - 1) < 1e-5)
        #expect(abs(simd_distance(g.positions[2], g.positions[3]) - 3) < 1e-5)
    }
}

struct ConstellationIdleTurnTests {
    private let idle = ConstellationIdleTurn.State(
        selected: 0, idle: .seconds(6), visible: true, reduceMotion: false, pressing: false
    )

    @Test func rotatesOnlyAfter5sIdleWithNothingSelectedVisibleMotionAllowed() {
        #expect(ConstellationIdleTurn.allowed(idle))
        var s = idle
        s.idle = .milliseconds(4999)
        #expect(!ConstellationIdleTurn.allowed(s))
        s = idle
        s.selected = 1
        #expect(!ConstellationIdleTurn.allowed(s))
        s = idle
        s.visible = false
        #expect(!ConstellationIdleTurn.allowed(s))
        s = idle
        s.reduceMotion = true
        #expect(!ConstellationIdleTurn.allowed(s))
        s = idle
        s.pressing = true
        #expect(!ConstellationIdleTurn.allowed(s))
    }

    @Test func stopsWhileASheetCoversTheScreen() {
        var s = idle
        s.covered = true
        #expect(!ConstellationIdleTurn.allowed(s))
    }

    @Test func everyStepIsRefusedOnceTheTurnHasRun90s() {
        var s = idle
        s.turned = .milliseconds(89_999)
        #expect(ConstellationIdleTurn.allowed(s))
        s.turned = .seconds(90)
        #expect(!ConstellationIdleTurn.allowed(s))
    }

    @Test func stepsNoMoreThan30TimesASecond() {
        #expect(Duration.seconds(1) / ConstellationIdleTurn.stepInterval <= 30)
        #expect(Duration.seconds(1) / ConstellationIdleTurn.stepInterval > 29.9)
    }

    @Test func turnsForAtMost90s() {
        #expect(ConstellationIdleTurn.continues(turned: .zero))
        #expect(ConstellationIdleTurn.continues(turned: .milliseconds(89_999)))
        #expect(!ConstellationIdleTurn.continues(turned: .seconds(90)))
        #expect(!ConstellationIdleTurn.continues(turned: .milliseconds(500), max: .milliseconds(400)))
    }

    @Test func turnsOnceInThreeMinutes() {
        #expect(abs(ConstellationIdleTurn.angle(after: .seconds(180)) - 2 * .pi) < 1e-9)
    }
}

struct ConstellationCameraRuleTests {
    @Test func startsTrueAgainWithAFreshGraph() {
        #expect(ConstellationRules.nextCameraAutoView(false, .freshGraph))
    }

    @Test func survivesAPressAloneProgrammaticMovesAndTheIdleTurn() {
        #expect(ConstellationRules.nextCameraAutoView(true, .press))
        #expect(ConstellationRules.nextCameraAutoView(true, .programmatic))
        #expect(ConstellationRules.nextCameraAutoView(true, .idleTurn))
        #expect(!ConstellationRules.nextCameraAutoView(false, .press))
    }

    @Test func endsWithARealOrbitAZoomOrAnExplicitCentre() {
        #expect(!ConstellationRules.nextCameraAutoView(true, .userOrbit))
        #expect(!ConstellationRules.nextCameraAutoView(true, .userZoom))
        #expect(!ConstellationRules.nextCameraAutoView(true, .centreOn))
    }

    @Test func easeRunsFrom0To1ThroughTheMiddle() {
        #expect(ConstellationRules.easeInOutCubic(0) == 0)
        #expect(abs(ConstellationRules.easeInOutCubic(0.5) - 0.5) < 0.005)
        #expect(ConstellationRules.easeInOutCubic(1) == 1)
        #expect(ConstellationRules.easeInOutCubic(2) == 1)
    }

    @Test func aimsAtARobustCentroidAndFitsThe95thPercentileRadiusNotAStrayPoint() {
        // Thirty-nine points on a ring of radius 10 round (5, 0, 0), and one 1000 away.
        var pts = (0 ..< 39).map { i -> SIMD3<Float> in
            let a = Float(i) / 39 * 2 * .pi
            return [5 + cos(a) * 10, sin(a) * 10, 0]
        }
        pts.append([1000, 0, 0])
        let f = ConstellationRules.frameCloud(pts, fieldOfView: 60, aspect: 1)
        #expect(abs(f.centre.x - 5) < 0.001)
        #expect(abs(f.centre.y) < 0.001)
        // Radius 10 with the margin, at a 30° half angle.
        #expect(abs(Double(f.distance) - 10 * ConstellationRules.frameMargin / 0.5) < 0.01)
    }

    @Test func standsFartherBackForANarrowPortraitView() {
        let pts: [SIMD3<Float>] = [[-10, 0, 0], [10, 0, 0]]
        let wide = ConstellationRules.frameCloud(pts, fieldOfView: 50, aspect: 1.6)
        let tall = ConstellationRules.frameCloud(pts, fieldOfView: 50, aspect: 0.5)
        #expect(abs(Double(wide.distance) - 10 * ConstellationRules.frameMargin / sin(25 * .pi / 180)) < 0.01)
        #expect(tall.distance > wide.distance)
    }

    @Test(arguments: [0.25, 0.46, 1, 2.4])
    func fitsTheWhole95thPercentileSphereAndLetsTheUserZoomBackOut(aspect: Double) {
        // 200 points on a sphere of radius 100: the 95th-percentile radius is exactly 100.
        let sphere = (0 ..< 200).map { i -> SIMD3<Float> in
            let y = 1 - 2 * (Float(i) + 0.5) / 200
            let r = (1 - y * y).squareRoot()
            let a = Float(i) * .pi * (3 - 5.0.squareRoot().float)
            return [cos(a) * r * 100, y * 100, sin(a) * r * 100]
        }
        let f = ConstellationRules.frameCloud(sphere, aspect: aspect)
        let fit = ConstellationRules.automaticFit(f.distance)
        let vHalf = Double(ConstellationRules.fieldOfView) * .pi / 360
        let hHalf = atan(tan(vHalf) * aspect)
        #expect(asin(100 / Double(fit.distance)) <= min(vHalf, hHalf) + 1e-3)
        #expect(abs(fit.distance - f.distance) < 1e-3)
        #expect(fit.maxDistance >= fit.distance)
        #expect(fit.maxDistance >= ConstellationRules.maxDistance)
    }

    @Test func keepsATinyGraphAtAComfortableDistanceAndTheZoomOutLimitAt600() {
        #expect(ConstellationRules.automaticFit(10).distance == 140)
        #expect(ConstellationRules.automaticFit(10).maxDistance == 600)
        #expect(ConstellationRules.automaticFit(450).maxDistance == 600)
    }
}

private extension Double {
    var float: Float { Float(self) }
}

struct ConstellationCameraTests {
    private let size = CGSize(width: 400, height: 800)

    @Test func theTargetIsInTheMiddleFromAnyDirection() {
        for (yaw, pitch) in [(Float(0), Float(0)), (1.2, 0.4), (-2.5, -1.1)] {
            let c = ConstellationCamera(target: [10, -5, 3], yaw: yaw, pitch: pitch, distance: 200)
            let p = c.project([[10, -5, 3]], radii: [1], size: size)
            #expect(abs(p.x[0] - 200) < 0.01)
            #expect(abs(p.y[0] - 400) < 0.01)
            #expect(abs(p.depth[0] - 200) < 0.01)
        }
    }

    @Test func rightIsRightUpIsUpAndBehindIsNaN() {
        let c = ConstellationCamera(target: .zero, yaw: 0, pitch: 0, distance: 100)
        let p = c.project([[10, 0, 0], [0, 10, 0], [0, 0, 150]], radii: [1, 1, 1], size: size)
        #expect(p.x[0] > 200)
        #expect(p.y[1] < 400)
        #expect(p.x[2].isNaN)
        // A world unit at depth 100 is pointsPerUnit / 100 points across.
        #expect(abs(p.radius[0] - ConstellationCamera.pointsPerUnit(size) / 100) < 0.01)
    }

    @Test func dragsOrbitAndPinchesZoomWithinTheLimits() {
        let base = ConstellationCamera(target: .zero, yaw: 0, pitch: 0, distance: 300)
        let orbited = base.orbited(from: base, by: CGSize(width: 100, height: 10_000), height: 800)
        #expect(orbited.yaw < 0)
        #expect(orbited.pitch == ConstellationCamera.pitchLimit)
        #expect(!orbited.autoView)
        #expect(orbited.distance == 300)
        #expect(base.zoomed(from: base, by: 2).distance == 150)
        #expect(base.zoomed(from: base, by: 1000).distance == ConstellationRules.minDistance)
        #expect(base.zoomed(from: base, by: 0.01).distance == ConstellationRules.maxDistance)
        #expect(base.zoomed(from: base, by: 0).distance == 300)
    }

    @Test func centringKeepsTheDirectionAndStandsAtAComfortableDistance() {
        let base = ConstellationCamera(target: .zero, yaw: 0.7, pitch: 0.3, distance: 300)
        let c = base.centred(on: [20, 30, 40])
        #expect(c.target == [20, 30, 40])
        #expect(c.distance == ConstellationRules.comfortDistance)
        #expect(simd_length(c.direction - base.direction) < 1e-6)
        #expect(!c.autoView)
    }

    /// The selection tray covers the bottom of the sky: a searched star is
    /// centred in the part above it, from the same direction.
    @Test func centringAboveTheTrayPutsTheStarInTheMiddleOfWhatIsUncovered() {
        for (yaw, pitch) in [(Float(0.7), Float(0.3)), (-2.0, -1.0)] {
            let base = ConstellationCamera(target: .zero, yaw: yaw, pitch: pitch, distance: 300)
            let c = base.centred(on: [20, 30, 40], bottomInset: 120, size: size)
            let p = c.project([[20, 30, 40]], radii: [1], size: size)
            #expect(abs(p.x[0] - 200) < 0.01)
            #expect(abs(p.y[0] - 340) < 0.01)
            #expect(c.distance == ConstellationRules.comfortDistance)
            #expect(simd_length(c.direction - base.direction) < 1e-6)
            #expect(!c.autoView)
        }
        // No inset: the plain centre. An inset past half the view is held there.
        let base = ConstellationCamera(target: .zero, yaw: 0, pitch: 0, distance: 300)
        #expect(base.centred(on: [1, 2, 3], bottomInset: 0, size: size).target == [1, 2, 3])
        let tall = base.centred(on: [1, 2, 3], bottomInset: 10_000, size: size)
        let q = tall.project([[1, 2, 3]], radii: [1], size: size)
        #expect(abs(q.y[0] - 200) < 0.01)
    }

    @Test func theIdleTurnTurnsAboutUpAndKeepsTheAutomaticView() {
        let base = ConstellationCamera(target: [1, 2, 3], yaw: 0, pitch: 0.2, distance: 250)
        let t = base.turned(by: 0.1)
        #expect(abs(t.yaw - 0.1) < 1e-6)
        #expect(t.pitch == base.pitch)
        #expect(t.target == base.target)
        #expect(abs(simd_distance(t.position, t.target) - 250) < 1e-3)
        #expect(t.autoView)
    }

    @Test func aFitFramesTheStarsFromTheSameDirection() {
        let base = ConstellationCamera(target: [50, 50, 50], yaw: 0.4, pitch: 0.1, distance: 20)
        let f = base.fitted(to: [[-100, 0, 0], [100, 0, 0], [0, 100, 0], [0, -100, 0]], aspect: 0.5)
        #expect(simd_length(f.target) < 1e-3)
        #expect(f.distance >= ConstellationRules.minFitDistance)
        #expect(simd_length(f.direction - base.direction) < 1e-6)
        #expect(base.fitted(to: [], aspect: 1) == base)
    }
}

struct ConstellationMeshTests {
    @Test func theRingIsOneBandOfTriangles() {
        let ring = ConstellationMeshes.ring(segments: 32)
        #expect(ring.positions.count == 64)
        #expect(ring.triangleCount == 64)
        #expect(ring.indices.allSatisfy { Int($0) < ring.positions.count })
    }

    @Test func everyLineIsTwoCrossedQuadsInItsSlotAndShortOnesAreLeftOut() {
        let g = ConstellationMeshes.lines([
            .init(a: [0, 0, 0], b: [10, 0, 0], slot: 2),
            .init(a: [0, 0, 0], b: [0, 10, 0], slot: 5),
            .init(a: [1, 1, 1], b: [1, 1, 1], slot: 0),
        ], width: 0.3)
        #expect(g.triangleCount == 8)
        #expect(g.faceMaterials == [2, 2, 2, 2, 5, 5, 5, 5])
        #expect(g.indices.allSatisfy { Int($0) < g.positions.count })
        // The quads are `width` across.
        #expect(abs(simd_distance(g.positions[0], g.positions[1]) - 0.3) < 1e-5)
        #expect(ConstellationMeshes.lines([], width: 0.3).isEmpty)
    }

    @Test func theFarSkyIsTheSameEveryTimeAndFarAway() {
        let a = ConstellationMeshes.backdrop(count: 600, radius: 1800)
        #expect(a == ConstellationMeshes.backdrop(count: 600, radius: 1800))
        #expect(a.triangleCount == 1200)
        #expect(a.positions.allSatisfy { simd_length($0) > 1400 })
    }
}
