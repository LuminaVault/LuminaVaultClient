// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphRealityView.swift
//
// HER-235 3D viz — RealityKit "living brain" renderer. Replaces the 2D
// `BrainGraphCanvas` with an orbitable 3D point-cloud: emissive spheres sized
// by score, colored by activity on the brand cyan→amber ramp, thin edges,
// drag-to-orbit + pinch-to-zoom, tap-to-select.
//
// Node placement uses the server's precomputed PCA coordinate
// (`MemoryGraphNodeDTO.position`); nodes without one fall back to a
// deterministic golden-spiral shell so nothing collapses to the origin.
//
// Glow note: RealityKit on iOS has no cheap post-process bloom (unlike
// SceneKit's `camera.bloomIntensity`). The glow here is emissive
// `UnlitMaterial` cores + a larger, low-opacity additive halo sphere per node.

import LuminaVaultShared
import RealityKit
import SwiftUI

struct BrainGraphRealityView: View {
    let graph: MemoryGraphResponse
    let onSelect: (UUID) -> Void

    // Orbit + zoom state (persist across gesture updates).
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var baseYaw: Float = 0
    @State private var basePitch: Float = 0
    @State private var zoom: Float = 1
    @State private var baseZoom: Float = 1

    /// Camera distance from the cluster centre at zoom == 1.
    private let baseDistance: Float = 220

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "graphRoot"
            content.add(root)
            Self.buildGraph(into: root, graph: graph)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 50
            camera.position = [0, 0, baseDistance]
            content.add(camera)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "graphRoot" }) else { return }
            // Apply orbit as a container rotation (yaw about Y, pitch about X).
            root.transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
            if let camera = content.entities.first(where: { $0 is PerspectiveCamera }) {
                camera.position = [0, 0, baseDistance / max(0.3, zoom)]
            }
        }
        .gesture(orbitGesture)
        .simultaneousGesture(zoomGesture)
        .gesture(tapGesture)
        .background(Color.black)
    }

    // MARK: - Gestures

    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                yaw = baseYaw + Float(value.translation.width) * 0.006
                pitch = max(-1.4, min(1.4, basePitch + Float(value.translation.height) * 0.006))
            }
            .onEnded { _ in baseYaw = yaw; basePitch = pitch }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = max(0.4, min(4, baseZoom * Float(value.magnification))) }
            .onEnded { _ in baseZoom = zoom }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let id = UUID(uuidString: value.entity.name) { onSelect(id) }
            }
    }

    // MARK: - Scene construction

    /// Layout scale: server coords are in a ±60 cube; spread them out a bit for
    /// the camera distance we use.
    private static let layoutScale: Float = 1.6

    private static func buildGraph(into root: Entity, graph: MemoryGraphResponse) {
        var positions: [UUID: SIMD3<Float>] = [:]
        let unplaced = graph.nodes.filter { $0.position == nil }
        var spiralIndex = 0

        for node in graph.nodes {
            let pos = position(for: node, spiralIndex: &spiralIndex, unplacedCount: unplaced.count)
            positions[node.id] = pos
            root.addChild(makeNodeEntity(node: node, position: pos))
        }

        // Edges: cap for perf on dense clouds; strongest weights win.
        let capped = graph.edges.sorted { $0.weight > $1.weight }.prefix(1200)
        for edge in capped {
            guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
            root.addChild(makeEdgeEntity(from: a, to: b, weight: Float(edge.weight)))
        }
    }

    private static func position(
        for node: MemoryGraphNodeDTO,
        spiralIndex: inout Int,
        unplacedCount: Int
    ) -> SIMD3<Float> {
        if let p = node.position {
            return SIMD3(Float(p.x), Float(p.y), Float(p.z)) * layoutScale
        }
        // Golden-spiral shell fallback — deterministic, evenly distributed.
        let i = spiralIndex
        spiralIndex += 1
        let count = max(1, unplacedCount)
        let phi = Float.pi * (3 - (5 as Float).squareRoot()) // golden angle
        let y = 1 - (Float(i) / Float(count)) * 2
        let radius = (1 - y * y).squareRoot()
        let theta = phi * Float(i)
        let shell: Float = 70
        return SIMD3(cos(theta) * radius, y, sin(theta) * radius) * shell
    }

    private static func makeNodeEntity(node: MemoryGraphNodeDTO, position: SIMD3<Float>) -> ModelEntity {
        let radius = radiusForScore(node.score)
        let activity = node.activity ?? activityFromCreatedAt(node.createdAt)
        let color = activityColor(activity)

        // Emissive core (unlit reads as self-illuminated → glow with the halo).
        let core = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [UnlitMaterial(color: color)]
        )
        core.position = position
        core.name = node.id.uuidString
        // Enable tap hit-testing.
        core.components.set(InputTargetComponent())
        core.generateCollisionShapes(recursive: false)

        // Faint larger halo sphere for the bloom-like glow. The low-alpha color
        // gives UnlitMaterial its translucency without touching the version-
        // fragile `.blending` setter.
        let halo = UnlitMaterial(color: color.withAlphaComponent(0.16))
        let haloEntity = ModelEntity(mesh: .generateSphere(radius: radius * 2.1), materials: [halo])
        core.addChild(haloEntity)

        return core
    }

    private static func makeEdgeEntity(from a: SIMD3<Float>, to b: SIMD3<Float>, weight: Float) -> ModelEntity {
        let mid = (a + b) / 2
        let length = simd_distance(a, b)
        let thickness = 0.15 + weight * 0.5
        let box = ModelEntity(
            mesh: .generateBox(size: [thickness, thickness, length]),
            materials: [UnlitMaterial(color: UIColor(white: 1, alpha: Double(0.10 + weight * 0.25)))]
        )
        box.position = mid
        // Orient the box's local +Z along (b - a).
        let dir = simd_normalize(b - a)
        box.orientation = simd_quatf(from: [0, 0, 1], to: dir)
        return box
    }

    // MARK: - Brand ramp (mirrors web brain-palette.ts)

    private static func radiusForScore(_ score: Double) -> Float {
        let norm = min(1, log1p(max(0, score)) / log1p(100))
        return Float(2 + norm * 6)
    }

    private static func activityFromCreatedAt(_ date: Date) -> Double {
        let ageDays = Date().timeIntervalSince(date) / 86_400
        return min(1, max(0, 1 - ageDays / 90))
    }

    /// Cyan → violet → amber, matching the app palette and the web ramp.
    private static func activityColor(_ activity: Double) -> UIColor {
        let t = min(1, max(0, activity))
        let cold = SIMD3<Double>(0, 0.83, 1) // #00d4ff
        let mid = SIMD3<Double>(0.49, 0.36, 1) // #7c5cff
        let hot = SIMD3<Double>(0.96, 0.62, 0.04) // #f59e0b
        let c: SIMD3<Double> = t < 0.5
            ? mix(cold, mid, t / 0.5)
            : mix(mid, hot, (t - 0.5) / 0.5)
        return UIColor(red: c.x, green: c.y, blue: c.z, alpha: 1)
    }

    private static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        a + (b - a) * t
    }
}
