// The Constellation's RealityKit scene: one entity per star, all sharing one
// sphere mesh (hubs and selection marks share one ring mesh, turned to the
// camera), a small set of unlit materials (one per colour in use, and its
// dimmed twin), one generated mesh for every line, one for the far sky, and
// the camera. Built once when the view is made and changed in place after
// that: `apply` compares what it is given with what it last drew and touches
// only what differs, so the camera, the entities and the meshes survive
// selection, filters and theme changes. Rules live in `ConstellationRules`.

import LuminaVaultShared
import RealityKit
import SwiftUI
import UIKit

/// The layout's answer for one graph: positions by id, whether it was laid
/// out from scratch, and a serial that changes with every answer.
nonisolated struct ConstellationPlacement: Sendable {
    var positions: [String: SIMD3<Float>]
    var fresh: Bool
    var serial: Int
}

@MainActor
final class ConstellationScene {
    private(set) var camera = ConstellationCamera()
    /// The view's size in points; the camera's aspect and the projection follow it.
    private(set) var size: CGSize = .zero

    private let root = Entity()
    private let cameraEntity = PerspectiveCamera()
    private let starsRoot = Entity()
    private let ringsRoot = Entity()
    private let lineEntity = ModelEntity()
    private let backdropEntity = ModelEntity()
    private var starMesh: MeshResource?
    private var ringMesh: MeshResource?
    private var stars: [ModelEntity] = []
    private var rings: [ModelEntity] = []
    private var materials = ConstellationMaterials()

    // What is drawn now.
    private(set) var model = ConstellationModel.empty
    /// World position per star of `model`; NaN until the layout has placed it.
    private(set) var points: [SIMD3<Float>] = []
    private(set) var look = ConstellationLook(tiers: [], lines: [], linesLit: false)
    private var theme: BrainGraphTheme?
    private var dark = true
    private var serial: Int?
    private var placedIDs = Set<String>()
    private var selectedStars: [Int] = []

    /// Called by the view's `make` closure, once.
    func install(into content: inout RealityViewCameraContent) {
        content.camera = .virtual
        cameraEntity.camera = PerspectiveCameraComponent(
            near: ConstellationCamera.near, far: ConstellationCamera.far,
            fieldOfViewInDegrees: ConstellationRules.fieldOfView, fieldOfViewOrientation: .vertical
        )
        root.addChild(starsRoot)
        root.addChild(ringsRoot)
        root.addChild(lineEntity)
        root.addChild(backdropEntity)
        content.add(root)
        content.add(cameraEntity)
        starMesh = MeshResource.generateSphere(radius: 1)
        ringMesh = ConstellationMeshes.meshResource(ConstellationMeshes.ring(), name: "ring")
        if let sky = ConstellationMeshes.meshResource(
            ConstellationMeshes.backdrop(count: ConstellationRules.backdropCount, radius: ConstellationRules.backdropRadius),
            name: "sky"
        ) {
            backdropEntity.model = ModelComponent(mesh: sky, materials: [])
        }
        backdropEntity.isEnabled = false
        // `make` is asynchronous: an `apply` may already have run against an
        // empty scene. Forget what it drew, so the next `update` draws it all.
        theme = nil
        serial = nil
        model = .empty
        placedIDs = []
        applyCamera()
    }

    // MARK: Updates

    /// Brings the scene up to date. Cheap when nothing changed. Returns
    /// whether the camera moved (an automatic fit).
    @discardableResult
    func apply(
        model next: ConstellationModel, placement: ConstellationPlacement?, highlight: BrainHighlight,
        theme nextTheme: BrainGraphTheme, dark nextDark: Bool
    ) -> Bool {
        let themeChanged = nextTheme != theme || nextDark != dark
        if themeChanged {
            theme = nextTheme
            dark = nextDark
            materials.reset(theme: nextTheme)
            let sky = materials.backdrop
            backdropEntity.model?.materials = [sky]
            backdropEntity.isEnabled = nextDark
        }
        let dataChanged = next.key != model.key || placement?.serial != serial || stars.count < next.ids.count
        var moved = false
        if dataChanged {
            let freshPlacement = placement.map { $0.fresh && $0.serial != serial } ?? false
            model = next
            serial = placement?.serial
            let nan = SIMD3<Float>(repeating: .nan)
            points = next.ids.map { placement?.positions[$0] ?? nan }
            let ids = Set(next.ids.indices.filter { points[$0].x.isFinite }.map { next.ids[$0] })
            let setChanged = ids != placedIDs
            placedIDs = ids
            placeStars()
            if freshPlacement { camera.autoView = ConstellationRules.nextCameraAutoView(camera.autoView, .freshGraph) }
            if freshPlacement || (camera.autoView && setChanged) { moved = fit() }
        }
        let nextLook = ConstellationRules.look(model, highlight: highlight)
        if dataChanged || themeChanged || nextLook != look {
            let linesChanged = dataChanged || themeChanged || nextLook.lines != look.lines || nextLook.linesLit != look.linesLit
            look = nextLook
            paintStars()
            if linesChanged { drawLines() }
            selectedStars = look.tiers.indices.filter { look.tiers[$0] == .selected && points[$0].x.isFinite }
            placeRings()
        }
        return moved
    }

    func resize(_ next: CGSize) -> Bool {
        guard next != size, next.width > 0, next.height > 0 else { return false }
        size = next
        if camera.autoView { return fit() }
        return false
    }

    /// Moves the camera entity to `camera`, and the selection rings with it.
    func setCamera(_ next: ConstellationCamera) {
        camera = next
        applyCamera()
    }

    /// Frames the placed stars from the current direction. Returns whether there was anything to frame.
    @discardableResult
    func fit() -> Bool {
        let placed = points.filter { $0.x.isFinite }
        guard !placed.isEmpty, size.width > 0, size.height > 0 else { return false }
        setCamera(camera.fitted(to: placed, aspect: Double(size.width / size.height)))
        return true
    }

    /// Where a star is, if it has been placed.
    func position(of id: String) -> SIMD3<Float>? {
        guard let i = model.index[id], i < points.count, points[i].x.isFinite else { return nil }
        return points[i]
    }

    /// Where every star is on screen now.
    func projection() -> ConstellationProjection {
        camera.project(points, radii: model.radius, size: size)
    }

    // MARK: Drawing

    private func applyCamera() {
        cameraEntity.position = camera.position
        cameraEntity.orientation = camera.orientation
        placeRings()
    }

    private func placeStars() {
        guard let starMesh, let ringMesh else { return }
        while stars.count < model.ids.count {
            let entity = ModelEntity()
            starsRoot.addChild(entity)
            stars.append(entity)
        }
        for (i, entity) in stars.enumerated() {
            guard i < model.ids.count, points[i].x.isFinite else {
                entity.isEnabled = false
                continue
            }
            let hub = model.isHub[i]
            let mesh = hub ? ringMesh : starMesh
            if entity.model?.mesh !== mesh { entity.model = ModelComponent(mesh: mesh, materials: []) }
            if hub, !entity.components.has(BillboardComponent.self) {
                entity.components.set(BillboardComponent())
            } else if !hub, entity.components.has(BillboardComponent.self) {
                entity.components.remove(BillboardComponent.self)
            }
            entity.position = points[i]
            entity.scale = SIMD3(repeating: model.radius[i])
            entity.isEnabled = true
        }
    }

    private func paintStars() {
        guard theme != nil else { return }
        for i in model.ids.indices where i < stars.count && points[i].x.isFinite {
            let dimmed = look.isDimmed(i)
            let material = model.isHub[i]
                ? materials.hub(dimmed: dimmed)
                : materials.star(model.colour[i], dimmed: dimmed)
            stars[i].model?.materials = [material]
        }
    }

    private func drawLines() {
        let slots = BrainLinkKindDTO.allCases
        var segments: [ConstellationMeshes.Segment] = []
        segments.reserveCapacity(look.lines.count)
        for e in look.lines {
            let edge = model.edges[e]
            let a = points[edge.a], b = points[edge.b]
            guard a.x.isFinite, b.x.isFinite else { continue }
            segments.append(.init(a: a, b: b, slot: UInt32(slots.firstIndex(of: edge.kind) ?? 0)))
        }
        let geometry = ConstellationMeshes.lines(segments, width: ConstellationRules.lineWidth)
        guard let mesh = ConstellationMeshes.meshResource(geometry, name: "lines") else {
            lineEntity.model = nil
            return
        }
        let alpha = ConstellationRules.lineAlpha(lit: look.linesLit, light: !dark)
        lineEntity.model = ModelComponent(mesh: mesh, materials: materials.lines(alpha: alpha))
    }

    /// A ring round each selected star, about `ringRadius` points on screen
    /// wherever the camera stands.
    private func placeRings() {
        guard let ringMesh else { return }
        while rings.count < selectedStars.count {
            let ring = ModelEntity(mesh: ringMesh, materials: [])
            ring.components.set(BillboardComponent())
            ringsRoot.addChild(ring)
            rings.append(ring)
        }
        let k = Float(ConstellationCamera.pointsPerUnit(size))
        let eye = camera.position
        for (r, ring) in rings.enumerated() {
            guard r < selectedStars.count, k > 0 else {
                ring.isEnabled = false
                continue
            }
            let i = selectedStars[r]
            let p = points[i]
            let screenRadius = Float(ConstellationRules.ringRadius) * simd_distance(p, eye) / k
            ring.position = p
            ring.scale = SIMD3(repeating: max(screenRadius, model.radius[i] * Float(ConstellationRules.ringToStar)))
            ring.model?.materials = [materials.selection]
            ring.isEnabled = true
        }
    }
}

// MARK: - Materials

/// The scene's materials: one per star colour in use (and its dimmed twin),
/// the hub ring, the selection ring, the far sky and one per connection kind.
/// Unlit and without tone mapping, so a palette colour is drawn as it is.
/// Dimming mixes toward the background (`dimIntensity` of the colour kept),
/// so dimmed stars stay opaque and need no sorting.
@MainActor
private struct ConstellationMaterials {
    private var theme: BrainGraphTheme?
    private var background = SIMD3<Double>(0, 0, 0)
    private var cache: [Key: UnlitMaterial] = [:]
    private(set) var selection = UnlitMaterial()
    private(set) var backdrop = UnlitMaterial()
    private var hubLit = UnlitMaterial()
    private var hubDim = UnlitMaterial()

    private struct Key: Hashable {
        var colour: Color
        var dimmed: Bool
    }

    mutating func reset(theme: BrainGraphTheme) {
        self.theme = theme
        cache.removeAll()
        background = Self.rgb(theme.background)
        selection = opaque(Self.rgb(theme.selection))
        hubLit = opaque(Self.rgb(theme.hub))
        hubDim = opaque(dim(Self.rgb(theme.hub)))
        let label = Self.rgb(theme.label)
        let a = ConstellationRules.backdropAlpha
        backdrop = opaque(label * a + background * (1 - a))
    }

    mutating func star(_ colour: Color, dimmed: Bool) -> UnlitMaterial {
        let key = Key(colour: colour, dimmed: dimmed)
        if let hit = cache[key] { return hit }
        let rgb = Self.rgb(colour)
        let made = opaque(dimmed ? dim(rgb) : rgb)
        cache[key] = made
        return made
    }

    func hub(dimmed: Bool) -> UnlitMaterial {
        dimmed ? hubDim : hubLit
    }

    /// One per `BrainLinkKindDTO.allCases`, in that order, at `alpha`.
    func lines(alpha: Float) -> [UnlitMaterial] {
        guard let theme else { return [] }
        return BrainLinkKindDTO.allCases.map { kind in
            var m = UnlitMaterial(applyPostProcessToneMap: false)
            m.color = .init(tint: Self.uiColor(Self.rgb(theme.link(kind))))
            m.blending = .transparent(opacity: .init(floatLiteral: alpha))
            m.faceCulling = .none
            m.writesDepth = false
            return m
        }
    }

    private func dim(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let k = ConstellationRules.dimIntensity
        return rgb * k + background * (1 - k)
    }

    private func opaque(_ rgb: SIMD3<Double>) -> UnlitMaterial {
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: Self.uiColor(rgb))
        m.faceCulling = .none
        return m
    }

    private static func rgb(_ colour: Color) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    private static func uiColor(_ rgb: SIMD3<Double>) -> UIColor {
        UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
    }
}
