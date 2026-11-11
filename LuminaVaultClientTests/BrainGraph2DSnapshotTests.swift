// LuminaVaultClient/LuminaVaultClientTests/BrainGraph2DSnapshotTests.swift
//
// The 2D Brain canvas on the 25-point fixture: at rest and with a selection,
// light and dark.
//
// New suite, so its snapshot cases are quarantined until CI's
// `record-snapshots` workflow has recorded the baselines on its iOS 26.4
// renderer — see `SnapshotQuarantine`. The render tests at the bottom are not
// snapshots and run everywhere: they check the canvas draws the graph at all
// (points in more than the background colour) from an injected, settled
// snapshot. Set `BRAIN_CANVAS_SHOTS` (as `TEST_RUNNER_BRAIN_CANVAS_SHOTS` on
// the xcodebuild command line) to a directory to also save what they drew.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient

// `nonisolated` with main-actor cases, rather than a main-actor class: the
// canvas draws on the main actor, and XCTestCase's initialisers and setUp are
// nonisolated, so a main-actor subclass warns under the default isolation.
nonisolated final class BrainGraph2DSnapshotTests: XCTestCase {
    private nonisolated static let size = CGSize(width: 390, height: 640)

    @MainActor
    private func canvas(
        _ fixture: BrainGraphCanvasFixture, selected: [String] = [], viewport: BrainGraphViewport? = nil, dark: Bool
    ) -> some View {
        BrainGraphCanvasFixtureHost(fixture: fixture, selected: selected, viewport: viewport)
            .frame(width: Self.size.width, height: Self.size.height)
            .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    @MainActor
    private func snap(_ view: some View, _ name: String, dark: Bool) {
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .sizeThatFits,
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            testName: name
        )
    }

    // MARK: - Cases

    @MainActor
    func testAtRest() throws {
        try SnapshotQuarantine.skipUnlessRecording()
        snap(canvas(.small, dark: false), "brain-2d-rest-light", dark: false)
        snap(canvas(.small, dark: true), "brain-2d-rest-dark", dark: true)
    }

    @MainActor
    func testWithASelection() throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let selected = [BrainGraphCanvasFixture.small.heaviestItem]
        snap(canvas(.small, selected: selected, dark: false), "brain-2d-selected-light", dark: false)
        snap(canvas(.small, selected: selected, dark: true), "brain-2d-selected-dark", dark: true)
    }

    // MARK: - Render

    /// Renders through `ImageRenderer`, counts the distinct colours drawn, and
    /// saves the PNG when asked to.
    @MainActor
    private func render(_ view: some View, _ name: String) throws -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "\(name) rendered nothing")
        if let dir = ProcessInfo.processInfo.environment["BRAIN_CANVAS_SHOTS"], let png = image.pngData() {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return try distinctColours(image)
    }

    @MainActor
    private func distinctColours(_ image: UIImage) throws -> Int {
        let cg = try XCTUnwrap(image.cgImage)
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drew)
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4 * 7) {
            // Coarse buckets, so antialiasing does not count as a colour.
            let key = UInt32(pixels[i] >> 4) << 8 | UInt32(pixels[i + 1] >> 4) << 4 | UInt32(pixels[i + 2] >> 4)
            seen.insert(key)
        }
        return seen.count
    }

    @MainActor
    func testTheCanvasDrawsTheSmallGraphLightAndDark() throws {
        let selected = [BrainGraphCanvasFixture.small.heaviestItem]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            XCTAssertGreaterThan(try render(canvas(.small, dark: dark), "small-rest-\(mode)"), 4)
            XCTAssertGreaterThan(try render(canvas(.small, selected: selected, dark: dark), "small-selected-\(mode)"), 4)
        }
    }

    /// The live path: no injected snapshot, so the canvas subscribes to its
    /// layout actor, sends the graph, and draws what the layout publishes,
    /// fitted once it settles. Hosted in a window, because only an on-screen
    /// view runs its `.task`.
    @MainActor
    func testALiveCanvasLaysTheGraphOutAndDrawsIt() async throws {
        let fixture = BrainGraphCanvasFixture.small
        let theme = BrainGraphTheme(palette: LVTheme.cyanGold.palette(for: .dark), scheme: .dark)
        let view = BrainGraphCanvas(
            graph: fixture.graph,
            highlight: BrainHighlight(selected: [], lit: nil),
            colourOf: fixture.colourOf(theme),
            onTap: { _, _ in },
            onBackgroundTap: {},
            onOpen: { _ in }
        )
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .dark))
        .environment(\.colorScheme, .dark)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "no window scene in the test host"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // Poll until the layout has drawn the graph, rather than sleeping a
        // fixed time: a fresh 25-point graph settles in about a second.
        func capture() -> UIImage {
            UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        let deadline = Date.now.addingTimeInterval(15)
        var image = capture()
        while try distinctColours(image) <= 4, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            image = capture()
        }
        // Then until it is at rest: two captures alike.
        var previous = image.pngData()
        while Date.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            image = capture()
            let now = image.pngData()
            if now == previous { break }
            previous = now
        }
        if let dir = ProcessInfo.processInfo.environment["BRAIN_CANVAS_SHOTS"], let png = image.pngData() {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("live-small-dark.png"))
        }
        XCTAssertGreaterThan(try distinctColours(image), 4, "the live canvas drew points")
    }

    @MainActor
    func testTheCanvasDrawsTheLargeGraphAndAZoomedView() throws {
        let fixture = BrainGraphCanvasFixture.large
        let fitted = BrainGraphCanvasLogic.fittedView(points: fixture.snapshot.points, size: Self.size)
        let zoomed = fitted.zoomed(by: 3, around: CGPoint(x: Self.size.width / 2, y: Self.size.height / 2))
        let selected = [fixture.heaviestItem]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            XCTAssertGreaterThan(try render(canvas(fixture, dark: dark), "large-rest-\(mode)"), 4)
            XCTAssertGreaterThan(try render(canvas(fixture, selected: selected, dark: dark), "large-selected-\(mode)"), 4)
            XCTAssertGreaterThan(try render(canvas(fixture, viewport: zoomed, dark: dark), "large-zoomed-\(mode)"), 4)
            XCTAssertGreaterThan(
                try render(canvas(.small, viewport: BrainGraphCanvasLogic.fittedView(
                    points: BrainGraphCanvasFixture.small.snapshot.points, size: Self.size
                ).zoomed(by: 2, around: CGPoint(x: 195, y: 320)), dark: dark), "small-zoomed-\(mode)"),
                4
            )
        }
    }
}
