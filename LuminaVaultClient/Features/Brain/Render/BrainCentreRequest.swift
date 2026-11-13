// Search's one explicit camera move. The screen hands the canvas a request to
// put a point in the middle; a new token makes picking the same point again a
// new request. Taps never send one: selecting never moves the camera.

import CoreGraphics

nonisolated struct BrainCentreRequest: Equatable, Sendable {
    var id: String
    var token: Int

    /// The view with `id` in the middle of a canvas of `size`, at the current
    /// zoom, or nil while that cannot be known (no size yet, the point is not
    /// laid out, positions not aligned with `ids`). `bottomInset` is what the
    /// selection tray covers at the bottom: the point goes in the middle of
    /// the part above it, so the tray never hides what search found.
    static func view(
        centring id: String, ids: [String], positions: [CGPoint], current: BrainGraphViewport, size: CGSize,
        bottomInset: CGFloat = 0
    ) -> BrainGraphViewport? {
        guard size.width > 0, size.height > 0, positions.count == ids.count,
              let at = ids.firstIndex(of: id) else { return nil }
        let point = positions[at]
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return current.centred(on: point, in: CGSize(width: size.width, height: size.height - heldInset(bottomInset, height: size.height)))
    }

    /// The tray's cover, never more than half the view, so a centred point
    /// stays on screen whatever the tray measures.
    static func heldInset(_ inset: CGFloat, height: CGFloat) -> CGFloat {
        guard inset.isFinite else { return 0 }
        return min(max(0, inset), height / 2)
    }
}
