// Where the Constellation's camera stands, as plain numbers: an orbit around a
// target (yaw, pitch, distance), the moves a finger makes (orbit, pinch), the
// renderer's own moves (fit, centre, idle turn), and the projection of a world
// point to the screen that picking and labels use. The RealityKit camera entity
// is set from `position` and `orientation`, with a vertical field of view of
// `ConstellationRules.fieldOfView`, so what is projected here is what is drawn.

import CoreGraphics
import Foundation
import simd

nonisolated struct ConstellationCamera: Equatable, Sendable {
    var target: SIMD3<Float> = .zero
    /// Turn about the world's up axis through the target; 0 looks down -z.
    var yaw: Float = 0
    /// Height of the camera over the target's horizon, radians.
    var pitch: Float = 0
    var distance: Float = 300
    var maxDistance: Float = ConstellationRules.maxDistance
    /// Still the automatic fit: refits when the set of stars changes.
    var autoView = true

    /// Pitch stays clear of straight up and down, where yaw stops meaning anything.
    static let pitchLimit: Float = 1.4
    static let near: Float = 0.5
    static let far: Float = 6000

    /// Unit vector from the target to the camera.
    var direction: SIMD3<Float> {
        SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    }

    var position: SIMD3<Float> { target + direction * distance }

    /// Turns the camera's -z onto the target with the world's up kept up.
    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
    }

    // MARK: Moves

    /// A one-finger drag of `translation` points since `base`, in a view
    /// `height` points tall: a full height turns the sky once (OrbitControls).
    func orbited(from base: ConstellationCamera, by translation: CGSize, height: CGFloat) -> ConstellationCamera {
        var next = self
        let k = Float(2 * Double.pi / Double(max(1, height)))
        next.yaw = base.yaw - Float(translation.width) * k
        next.pitch = min(Self.pitchLimit, max(-Self.pitchLimit, base.pitch + Float(translation.height) * k))
        next.autoView = ConstellationRules.nextCameraAutoView(autoView, .userOrbit)
        return next
    }

    /// A pinch of `magnification` since `base`: nearer as the fingers spread.
    func zoomed(from base: ConstellationCamera, by magnification: CGFloat) -> ConstellationCamera {
        guard magnification.isFinite, magnification > 0 else { return self }
        var next = self
        next.distance = min(maxDistance, max(ConstellationRules.minDistance, base.distance / Float(magnification)))
        next.autoView = ConstellationRules.nextCameraAutoView(autoView, .userZoom)
        return next
    }

    /// Frames the stars from the current direction (an automatic fit).
    func fitted(to points: [SIMD3<Float>], aspect: Double) -> ConstellationCamera {
        guard !points.isEmpty else { return self }
        let frame = ConstellationRules.frameCloud(points, aspect: aspect)
        let fit = ConstellationRules.automaticFit(frame.distance)
        var next = self
        next.target = frame.centre
        next.distance = fit.distance
        next.maxDistance = fit.maxDistance
        return next
    }

    /// The star at `point` in the middle, `comfortDistance` away, seen from
    /// the same direction. An explicit request: no longer automatic.
    func centred(on point: SIMD3<Float>) -> ConstellationCamera {
        var next = self
        next.target = point
        next.distance = ConstellationRules.comfortDistance
        next.autoView = ConstellationRules.nextCameraAutoView(autoView, .centreOn)
        return next
    }

    /// The idle turn: `angle` radians about the world's up axis.
    func turned(by angle: Double) -> ConstellationCamera {
        var next = self
        next.yaw = yaw + Float(angle)
        next.autoView = ConstellationRules.nextCameraAutoView(autoView, .idleTurn)
        return next
    }

    /// Part way from this camera to `other` (an eased centre): target and
    /// distance blended, direction kept.
    func interpolated(to other: ConstellationCamera, fraction t: Double) -> ConstellationCamera {
        var next = other
        let f = Float(t)
        next.target = target + (other.target - target) * f
        next.distance = distance + (other.distance - distance) * f
        next.yaw = yaw + (other.yaw - yaw) * f
        next.pitch = pitch + (other.pitch - pitch) * f
        return next
    }

    // MARK: Projection

    /// Screen points per world unit at a depth of 1, in a view of `size`.
    static func pointsPerUnit(_ size: CGSize) -> CGFloat {
        size.height / (2 * CGFloat(tan(Double(ConstellationRules.fieldOfView) * .pi / 360)))
    }

    /// Projects `points` (with world `radii`) into a view of `size`: screen
    /// x, y (y down), depth in front of the camera, and the core's radius in
    /// points. A point behind the camera is NaN.
    func project(_ points: [SIMD3<Float>], radii: [Float], size: CGSize) -> ConstellationProjection {
        var out = ConstellationProjection()
        out.size = size
        out.x.reserveCapacity(points.count)
        out.y.reserveCapacity(points.count)
        out.depth.reserveCapacity(points.count)
        out.radius.reserveCapacity(points.count)
        let inverse = orientation.inverse
        let eye = position
        let k = Self.pointsPerUnit(size)
        for (i, p) in points.enumerated() {
            let v = inverse.act(p - eye)
            let depth = CGFloat(-v.z)
            guard depth > 1e-6, p.x.isFinite, p.y.isFinite, p.z.isFinite else {
                out.x.append(.nan)
                out.y.append(.nan)
                out.depth.append(.nan)
                out.radius.append(0)
                continue
            }
            out.x.append(size.width / 2 + CGFloat(v.x) * k / depth)
            out.y.append(size.height / 2 - CGFloat(v.y) * k / depth)
            out.depth.append(depth)
            out.radius.append(i < radii.count ? CGFloat(radii[i]) * k / depth : 0)
        }
        return out
    }
}
