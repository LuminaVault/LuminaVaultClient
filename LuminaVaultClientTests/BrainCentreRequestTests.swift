// Search's one explicit camera move: the view that puts a point in the middle
// of the canvas, at the current zoom.

import CoreGraphics
@testable import LuminaVaultClient
import Testing

struct BrainCentreRequestTests {
    private let size = CGSize(width: 400, height: 800)

    @Test func centresTheNamedPointAtTheCurrentScale() throws {
        let current = BrainGraphViewport(scale: 2, offset: CGPoint(x: 10, y: 20), isAutomatic: true)
        let view = try #require(BrainCentreRequest.view(
            centring: "b", ids: ["a", "b"], positions: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: -40)],
            current: current, size: size
        ))
        #expect(view.scale == 2)
        #expect(!view.isAutomatic)
        let onScreen = view.screen(CGPoint(x: 30, y: -40))
        #expect(abs(onScreen.x - 200) < 0.001)
        #expect(abs(onScreen.y - 400) < 0.001)
    }

    /// The tray covers the bottom of the canvas: the point goes in the middle
    /// of what is left above it. An inset past half the canvas is held there.
    @Test func centresAboveTheTray() throws {
        let current = BrainGraphViewport(scale: 2, offset: .zero, isAutomatic: true)
        let view = try #require(BrainCentreRequest.view(
            centring: "a", ids: ["a"], positions: [CGPoint(x: 30, y: -40)],
            current: current, size: size, bottomInset: 120
        ))
        let onScreen = view.screen(CGPoint(x: 30, y: -40))
        #expect(abs(onScreen.x - 200) < 0.001)
        #expect(abs(onScreen.y - 340) < 0.001)
        let held = try #require(BrainCentreRequest.view(
            centring: "a", ids: ["a"], positions: [CGPoint(x: 30, y: -40)],
            current: current, size: size, bottomInset: 5_000
        ))
        #expect(abs(held.screen(CGPoint(x: 30, y: -40)).y - 200) < 0.001)
    }

    @Test func anUnknownPointOrNoSizeMovesNothing() {
        let current = BrainGraphViewport.initial
        #expect(BrainCentreRequest.view(
            centring: "z", ids: ["a"], positions: [.zero], current: current, size: size
        ) == nil)
        #expect(BrainCentreRequest.view(
            centring: "a", ids: ["a"], positions: [.zero], current: current, size: .zero
        ) == nil)
        // Positions not aligned with the ids yet (no snapshot): wait.
        #expect(BrainCentreRequest.view(
            centring: "a", ids: ["a"], positions: [], current: current, size: size
        ) == nil)
    }

    @Test func aNonFinitePositionMovesNothing() {
        #expect(BrainCentreRequest.view(
            centring: "a", ids: ["a"], positions: [CGPoint(x: CGFloat.nan, y: 0)],
            current: .initial, size: size
        ) == nil)
    }

    @Test func eachPickIsANewRequest() {
        let first = BrainCentreRequest(id: "a", token: 1)
        let again = BrainCentreRequest(id: "a", token: 2)
        #expect(first != again)
    }
}
