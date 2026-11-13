// The Constellation's RealityKit scene, driven without a RealityView: what
// `apply` keeps and what it rebuilds when the inputs change.

import Foundation
import simd
import SwiftUI
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

private enum SceneFixture {
    @MainActor static let theme = BrainGraphTheme(palette: LVTheme.cyanGold.palette(for: .dark), scheme: .dark)
    @MainActor static let lightTheme = BrainGraphTheme(palette: LVTheme.cyanGold.palette(for: .light), scheme: .light)

    /// The ten-note graph, for the layout.
    nonisolated static func graphForLayout() -> VisibleBrainGraph {
        graph(10)
    }

    /// `count` notes, n0 linked to every other one.
    nonisolated static func graph(_ count: Int, hidden: Set<String> = []) -> VisibleBrainGraph {
        let ids = (0 ..< count).map { "n\($0)" }.filter { !hidden.contains($0) }
        let nodes = ids.map { BrainGraphNodeDTO(id: $0, kind: .note, label: $0, weight: 2) }
        let edges = ids.dropFirst().filter { _ in ids.first == "n0" }
            .map { BrainGraphEdgeDTO(from: "n0", to: $0, kind: .link) }
        let raw = BrainGraphResponse(generatedAt: Date(timeIntervalSince1970: 0), vaults: [], nodes: nodes, edges: edges)
        return BrainGraphModel.visible(raw, filters: BrainGraphModel.defaultFilters())
    }

    nonisolated static func model(_ graph: VisibleBrainGraph) -> ConstellationModel {
        ConstellationModel(graph: graph) { _ in .red }
    }

    /// Stars on a circle of radius 50.
    nonisolated static func placement(_ graph: VisibleBrainGraph, serial: Int, fresh: Bool) -> ConstellationPlacement {
        var positions: [String: SIMD3<Float>] = [:]
        for (i, node) in graph.nodes.enumerated() {
            let a = Float(i) / Float(max(1, graph.nodes.count)) * 2 * .pi
            positions[node.id] = [cos(a) * 50, sin(a) * 50, Float(i % 3) * 10]
        }
        return ConstellationPlacement(positions: positions, fresh: fresh, serial: serial)
    }

    nonisolated static func highlight(_ graph: VisibleBrainGraph, _ selected: Set<String>) -> BrainHighlight {
        BrainHighlight(selected: selected, lit: selected.isEmpty ? nil : BrainGraphModel.litSet(graph.index, ids: selected))
    }

    @MainActor static func scene() -> ConstellationScene {
        let scene = ConstellationScene()
        scene.prepare()
        _ = scene.resize(CGSize(width: 390, height: 700))
        return scene
    }
}

@MainActor
struct ConstellationSceneDataChangeTests {
    /// A star with a high index selected, then the data shrinks under it (a
    /// filter, a vault change, a reload): the automatic camera refits, and
    /// the selection rings must not read the old model's indices.
    @Test func aSelectedStarSurvivesTheGraphShrinkingUnderIt() {
        let scene = SceneFixture.scene()
        let ten = SceneFixture.graph(10)
        scene.apply(
            model: SceneFixture.model(ten), placement: SceneFixture.placement(ten, serial: 1, fresh: true),
            highlight: SceneFixture.highlight(ten, ["n9"]), theme: SceneFixture.theme, dark: true
        )
        #expect(scene.selectedStarIndices == [9])
        let three = SceneFixture.graph(3)
        scene.apply(
            model: SceneFixture.model(three), placement: SceneFixture.placement(three, serial: 2, fresh: false),
            highlight: SceneFixture.highlight(ten, ["n9"]), theme: SceneFixture.theme, dark: true
        )
        #expect(scene.selectedStarIndices.isEmpty)
        #expect(scene.model.ids.count == 3)
    }
}

@MainActor
struct ConstellationSceneUpdateTests {
    private let ten = SceneFixture.graph(10)

    private func placed() -> ConstellationScene {
        let scene = SceneFixture.scene()
        scene.apply(
            model: SceneFixture.model(ten), placement: SceneFixture.placement(ten, serial: 1, fresh: true),
            highlight: SceneFixture.highlight(ten, []), theme: SceneFixture.theme, dark: true
        )
        return scene
    }

    @Test func aHighlightChangeKeepsTheCameraAndRebuildsLinesOnlyWhenTheLitSetMoves() {
        let scene = placed()
        let camera = scene.camera
        let builds = scene.lineBuilds
        let model = SceneFixture.model(ten)
        let placement = SceneFixture.placement(ten, serial: 1, fresh: true)
        let moved = scene.apply(
            model: model, placement: placement, highlight: SceneFixture.highlight(ten, ["n3"]),
            theme: SceneFixture.theme, dark: true
        )
        #expect(!moved)
        #expect(scene.camera == camera)
        #expect(scene.lineBuilds == builds + 1)
        #expect(scene.selectedStarIndices == [3])
        // The same highlight again: nothing to do.
        scene.apply(
            model: model, placement: placement, highlight: SceneFixture.highlight(ten, ["n3"]),
            theme: SceneFixture.theme, dark: true
        )
        #expect(scene.lineBuilds == builds + 1)
        #expect(scene.camera == camera)
    }

    @Test func aDataChangeKeepsACameraTheUserHasMoved() {
        let scene = placed()
        var held = scene.camera.orbited(from: scene.camera, by: CGSize(width: 80, height: 20), height: 700)
        held.autoView = false
        scene.setCamera(held)
        let builds = scene.lineBuilds
        let nine = SceneFixture.graph(10, hidden: ["n7"])
        let moved = scene.apply(
            model: SceneFixture.model(nine), placement: SceneFixture.placement(nine, serial: 2, fresh: false),
            highlight: SceneFixture.highlight(nine, []), theme: SceneFixture.theme, dark: true
        )
        #expect(!moved)
        #expect(scene.camera == held)
        // The data changed: the lines are rebuilt once.
        #expect(scene.lineBuilds == builds + 1)
    }

    @Test func aThemeChangeKeepsTheCameraAndRecoloursTheLinesWithoutRebuildingThem() {
        let scene = placed()
        let camera = scene.camera
        let builds = scene.lineBuilds
        scene.apply(
            model: SceneFixture.model(ten), placement: SceneFixture.placement(ten, serial: 1, fresh: true),
            highlight: SceneFixture.highlight(ten, []), theme: SceneFixture.lightTheme, dark: false
        )
        #expect(scene.camera == camera)
        #expect(scene.lineBuilds == builds)
    }

    @Test func aZoomRebuildsTheLinesSoTheyKeepTheirWidthAndStarsStayWithinTheirBounds() {
        let scene = placed()
        let builds = scene.lineBuilds
        scene.setCamera(scene.camera.zoomed(from: scene.camera, by: 20))
        #expect(scene.lineBuilds == builds + 1)
        let p = scene.projection()
        let top = ConstellationRules.maxStarPoints * ConstellationRules.coreShare
        for i in 0 ..< p.count where p.depth[i].isFinite {
            #expect(p.radius[i] <= top + 1e-6)
            #expect(p.radius[i] >= ConstellationRules.minStarPoints * ConstellationRules.coreShare - 1e-6)
        }
    }

    /// The scale each placed star should be drawn at for the scene's camera and size now.
    private func expectedScales(_ scene: ConstellationScene) -> [Int: Float] {
        let p = scene.projection()
        let k = ConstellationCamera.pointsPerUnit(scene.size)
        var out: [Int: Float] = [:]
        for i in 0 ..< p.count where p.depth[i].isFinite {
            out[i] = ConstellationRules.drawnScale(radius: p.radius[i], depth: p.depth[i], pointsPerUnit: k)
        }
        return out
    }

    /// Rotation or a split view with a camera the user has moved: stars are
    /// held to their size on screen for the new size at once, and the lines
    /// are rebuilt for it, not at the next camera move.
    @Test func aResizeWithAMovedCameraRedrawsStarsAndLinesForTheNewSize() {
        let scene = placed()
        // Close in, so stars sit on the largest size a star is drawn at, which
        // is a size in points: its world scale follows the view's height.
        var held = scene.camera.zoomed(from: scene.camera, by: 20)
        held.autoView = false
        scene.setCamera(held)
        let before = expectedScales(scene)
        let builds = scene.lineBuilds
        let moved = scene.resize(CGSize(width: 700, height: 390))
        #expect(!moved)
        #expect(scene.camera == held)
        let after = expectedScales(scene)
        #expect(!after.isEmpty)
        #expect(after.contains { i, s in abs((before[i] ?? s) - s) > 1e-4 }, "the fixture must reach a size-dependent clamp")
        for (i, s) in after {
            let drawn = scene.drawnScale(ofStar: i)
            #expect(drawn.map { abs($0 - s) <= 1e-4 * max(1, abs(s)) } == true, "star \(i): \(String(describing: drawn)) vs \(s)")
        }
        #expect(scene.lineBuilds == builds + 1)
        // The same size again does nothing.
        _ = scene.resize(CGSize(width: 700, height: 390))
        #expect(scene.lineBuilds == builds + 1)
    }

    /// The idle turn sets the camera thirty times a second: a step that
    /// changes no star's size writes no scale.
    @Test func anUnchangedCameraWritesNoStarScales() {
        let scene = placed()
        let writes = scene.scaleWrites
        scene.setCamera(scene.camera)
        #expect(scene.scaleWrites == writes)
        scene.setCamera(scene.camera.zoomed(from: scene.camera, by: 20))
        #expect(scene.scaleWrites > writes)
        let afterZoom = scene.scaleWrites
        scene.setCamera(scene.camera)
        #expect(scene.scaleWrites == afterZoom)
    }

    /// One projection per camera step, shared with the labels.
    @Test func setCameraReturnsTheProjectionItDrewWith() {
        let scene = placed()
        let p = scene.setCamera(scene.camera.turned(by: 0.1))
        #expect(p == scene.projection())
        #expect(p.count == 10)
    }
}

struct ConstellationLayoutStateTests {
    private let graph = SceneFixture.graphForLayout()

    @Test func theRunnerRemembersNothingOnItsOwn() async {
        let runner = ConstellationLayoutRunner()
        let first = await runner.layout(graph, from: ConstellationLayout())
        let again = await runner.layout(graph, from: ConstellationLayout())
        #expect(first?.fresh == true)
        #expect(again?.fresh == true)
    }

    @Test func aDroppedRunLeavesTheMemoryAsItWas() async throws {
        let runner = ConstellationLayoutRunner()
        var state = ConstellationLayoutState()
        let run = try #require(await runner.layout(graph, from: state.memory))
        let dropped = state.accept(run, cancelled: true)
        #expect(dropped == nil)
        #expect(state.serial == 0)
        // The next layout is measured against what is on screen: nothing.
        let next = try #require(await runner.layout(graph, from: state.memory))
        #expect(next.fresh)
    }

    @Test func anAcceptedRunIsRememberedAndNumbered() async throws {
        let runner = ConstellationLayoutRunner()
        var state = ConstellationLayoutState()
        let run = try #require(await runner.layout(graph, from: state.memory))
        let accepted = state.accept(run, cancelled: false)
        let placement = try #require(accepted)
        #expect(placement.serial == 1)
        #expect(placement.fresh)
        let next = try #require(await runner.layout(graph, from: state.memory))
        #expect(!next.fresh)
    }
}
