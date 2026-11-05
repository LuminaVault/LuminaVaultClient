// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/SettingsDataAccessStartTests.swift
//
// Settings opened from a Quick Assistant permission card starts with Data Access
// pushed, and Back must land on the Settings root and stay there. `SettingsRootView`
// seeds `showingDataAccess` in its init for that reason: a `.task` or `.onAppear`
// that sets it runs again when the root reappears on Back.
//
// This tests the mechanism on a stand-in stack with the same `navigationDestination`
// wiring, in both forms. Hosting the real `SettingsRootView` in the unit-test host
// aborts the host process within 0.1 s (the Xcode 26.2 "pointer being freed was not
// allocated" abort), so it could not be driven here; see the Task 10 fix report.
@testable import LuminaVaultClient
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsDataAccessStartTests: XCTestCase {
    /// How `SettingsRootView` seeds the push now.
    private struct SeededInInit: View {
        @State private var showing: Bool
        init(start: Bool) { _showing = State(initialValue: start) }

        var body: some View {
            NavigationStack {
                Text("root")
                    .navigationDestination(isPresented: $showing) { Text("data access") }
            }
        }
    }

    /// How it did before: the seed repeats whenever the root's task runs again.
    private struct SeededInTask: View {
        let start: Bool
        @State private var showing = false

        var body: some View {
            NavigationStack {
                Text("root")
                    .navigationDestination(isPresented: $showing) { Text("data access") }
                    .onAppear { if start { showing = true } }
            }
        }
    }

    private func navigationController(in view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let nav = current as? UINavigationController { return nav }
            responder = current.next
        }
        return view.subviews.lazy.compactMap { self.navigationController(in: $0) }.first
    }

    private func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Returns the stack depths: on open, then after Back.
    private func depths(of root: some View) async throws -> (opened: Int, afterBack: Int) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let controller = UIHostingController(rootView: root)
        window.rootViewController = controller
        controller.view.layoutIfNeeded()
        await settle(0.6)
        let nav = try XCTUnwrap(navigationController(in: controller.view))
        let opened = nav.viewControllers.count
        nav.popViewController(animated: false) // what Back does
        await settle(1.0)
        return (opened, nav.viewControllers.count)
    }

    func testSeedInInitStaysOnTheRootAfterBack() async throws {
        let result = try await depths(of: SeededInInit(start: true))
        XCTAssertEqual(result.opened, 2, "Data Access is pushed on open")
        XCTAssertEqual(result.afterBack, 1, "Back must stay on the root")
    }

    func testPlainOpenStaysAtTheRoot() async throws {
        let result = try await depths(of: SeededInInit(start: false))
        XCTAssertEqual(result.opened, 1)
    }

    /// Documents the failure the init form avoids.
    func testSeedInAppearRepushesOnBack() async throws {
        let result = try await depths(of: SeededInTask(start: true))
        XCTAssertEqual(result.opened, 2)
        XCTAssertEqual(result.afterBack, 2, "the onAppear form traps the user: this is the bug")
    }
}
