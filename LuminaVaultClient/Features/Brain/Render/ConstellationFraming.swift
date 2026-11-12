// How the Constellation's camera frames the sky: when the view stops being
// the automatic fit, where an automatic fit aims and how far back it stands,
// and the ease a centring move follows. Pure; a port of the web app's
// `render-3d-helpers.ts`.

import Foundation
import simd

/// What can happen to the camera, as far as "is it still the automatic fit" goes.
nonisolated enum ConstellationCameraEvent: Sendable {
    case freshGraph, press, userOrbit, userZoom, centreOn, programmatic, idleTurn
}

nonisolated extension ConstellationRules {
    /// Whether the camera is still the automatic fit after `event`. A fresh
    /// graph returns to it; a real orbit or zoom, or an explicit centre,
    /// leaves it; a press alone, the renderer's own moves and the idle turn do not.
    static func nextCameraAutoView(_ autoView: Bool, _ event: ConstellationCameraEvent) -> Bool {
        switch event {
        case .freshGraph: true
        case .userOrbit, .userZoom, .centreOn: false
        case .press, .programmatic, .idleTurn: autoView
        }
    }

    /// Where to aim and how far back to stand to frame the stars: a robust
    /// centroid (the mean of the points within the `share` percentile of
    /// distance from the plain mean), and the distance that fits the
    /// `share`-percentile radius around it, times `frameMargin`, into the
    /// narrower of the camera's two angles. The caller clamps the distance.
    static func frameCloud(
        _ points: [SIMD3<Float>], fieldOfView: Float = fieldOfView, aspect: Double, share: Double = frameShare
    ) -> (centre: SIMD3<Float>, distance: Float) {
        let n = Double(max(1, points.count))
        var c = SIMD3<Double>.zero
        for p in points { c += SIMD3<Double>(p) / n }
        // Distances are kept at Float precision, as the web keeps them in a
        // Float32Array: points mirrored about the centre then tie exactly and
        // the cut keeps or drops both, so a symmetric cloud stays centred.
        func distances(from c: SIMD3<Double>) -> [Double] {
            points.map { Double(Float(simd_length(SIMD3<Double>($0) - c))) }
        }
        func percentile(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let s = values.sorted()
            return s[max(0, Int((Double(s.count) * share).rounded(.up)) - 1)]
        }
        let d = distances(from: c)
        let cut = percentile(d)
        // One trimming pass: re-centre on the points inside the cut.
        var r = SIMD3<Double>.zero
        var k = 0.0
        for (i, p) in points.enumerated() where d[i] <= cut {
            r += SIMD3<Double>(p)
            k += 1
        }
        if k > 0 { c = r / k }
        let radius = percentile(distances(from: c))
        let vHalf = Double(fieldOfView) * .pi / 360
        let hHalf = atan(tan(vHalf) * max(1e-3, aspect))
        return (SIMD3<Float>(c), Float(radius * frameMargin / sin(min(vHalf, hHalf))))
    }

    /// How far an automatic fit stands, and how far the user may then zoom
    /// out: `maxDistance`, or the fit's own distance when that is farther.
    static func automaticFit(_ distance: Float) -> (distance: Float, maxDistance: Float) {
        let d = min(maxFitDistance, max(minFitDistance, distance))
        return (d, max(maxDistance, d))
    }

    static func easeInOutCubic(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
