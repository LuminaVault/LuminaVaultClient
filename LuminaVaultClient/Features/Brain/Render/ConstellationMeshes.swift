// The Constellation's generated geometry, as plain vertex and index arrays:
// the ring every hub and selection mark shares, the lines (one mesh for all of
// them, rebuilt only when the lit set or the data changes) and the far sky.
// `meshResource` turns one into a RealityKit mesh; everything else is pure.

import Foundation
import RealityKit

nonisolated struct ConstellationGeometry: Equatable, Sendable {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    /// Material slot per triangle; empty for a single-material mesh.
    var faceMaterials: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }
}

nonisolated enum ConstellationMeshes {
    /// One line segment: its ends and the material slot (the connection kind).
    nonisolated struct Segment: Equatable, Sendable {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var slot: UInt32
    }

    /// A flat ring of outer radius 1 in the xy plane, facing +z; drawn
    /// double-sided and turned to the camera by a billboard.
    static func ring(segments: Int = 32, inner: Float = 0.74) -> ConstellationGeometry {
        var g = ConstellationGeometry()
        for s in 0 ..< segments {
            let angle = Float(s) / Float(segments) * 2 * .pi
            let c = cos(angle), n = sin(angle)
            g.positions.append([c, n, 0])
            g.positions.append([c * inner, n * inner, 0])
        }
        for s in 0 ..< segments {
            let o = UInt32(s * 2), i = o + 1
            let o2 = UInt32(((s + 1) % segments) * 2), i2 = o2 + 1
            g.indices += [o, o2, i, o2, i2, i]
        }
        return g
    }

    /// Every segment as two crossed quads `width` wide, so a line keeps its
    /// width from any side: four triangles a line, each in the line's slot.
    /// Segments too short to have a direction are left out.
    static func lines(_ segments: [Segment], width: Float) -> ConstellationGeometry {
        var g = ConstellationGeometry()
        g.positions.reserveCapacity(segments.count * 8)
        g.indices.reserveCapacity(segments.count * 12)
        g.faceMaterials.reserveCapacity(segments.count * 4)
        let half = width / 2
        for s in segments {
            let d = s.b - s.a
            let len = simd_length(d)
            guard len > 1e-4, len.isFinite else { continue }
            let dir = d / len
            let helper: SIMD3<Float> = abs(dir.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(dir, helper)) * half
            let v = simd_normalize(simd_cross(dir, u)) * half
            for side in [u, v] {
                let base = UInt32(g.positions.count)
                g.positions += [s.a + side, s.a - side, s.b - side, s.b + side]
                g.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
                g.faceMaterials += [s.slot, s.slot]
            }
        }
        return g
    }

    /// The far sky: `count` small squares on a shell about `radius` out, each
    /// facing the middle, in hashed directions so the sky is the same every time.
    static func backdrop(count: Int, radius: Float) -> ConstellationGeometry {
        var g = ConstellationGeometry()
        for i in 0 ..< count {
            let h = BrainIDHash.mix32(UInt32(truncatingIfNeeded: i) &* 0x9E37_79B9 &+ 0x5EED)
            var dir = SIMD3<Float>(
                Float(BrainIDHash.jitter(hash: h, axis: 0)),
                Float(BrainIDHash.jitter(hash: h, axis: 1)),
                Float(BrainIDHash.jitter(hash: h, axis: 2))
            )
            if simd_length(dir) < 1e-3 { dir = [0, 0, 1] }
            dir = simd_normalize(dir)
            let far = radius * (0.85 + 0.3 * (Float(BrainIDHash.jitter(hash: h, axis: 3)) + 0.5))
            let size = 2 + 3 * (Float(BrainIDHash.jitter(hash: h, axis: 4)) + 0.5)
            let centre = dir * far
            let helper: SIMD3<Float> = abs(dir.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(dir, helper)) * size / 2
            let v = simd_normalize(simd_cross(dir, u)) * size / 2
            let base = UInt32(g.positions.count)
            g.positions += [centre - u - v, centre + u - v, centre + u + v, centre - u + v]
            g.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return g
    }

    /// A RealityKit mesh of `geometry`, or nil when it is empty or cannot be made.
    @MainActor
    static func meshResource(_ geometry: ConstellationGeometry, name: String) -> MeshResource? {
        guard !geometry.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(geometry.positions)
        d.primitives = .triangles(geometry.indices)
        if !geometry.faceMaterials.isEmpty { d.materials = .perFace(geometry.faceMaterials) }
        return try? MeshResource.generate(from: [d])
    }
}
