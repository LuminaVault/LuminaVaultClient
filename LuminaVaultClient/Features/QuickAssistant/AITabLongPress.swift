// LuminaVaultClient/LuminaVaultClient/Features/QuickAssistant/AITabLongPress.swift
//
// Long-pressing the AI tab. SwiftUI's `Tab` exposes no gesture, so this finds the
// `UITabBarController` behind the `TabView` with public API and puts one
// recogniser on its `tabBar`.
//
// The delegate is what keeps the tab bar behaving as before, and the spike
// tried the alternatives:
//  * Recognising simultaneously fires, but also selects the tab.
//  * Recognising alone never fires, because the bar's own gestures win.
//  * Making the bar's gestures wait for this one to fail is what works: a tap
//    ends before 0.4s, this fails, and the tap goes through as normal.
//
// Only gestures inside the bar are made to wait, so nothing on a tab's content
// is ever delayed. A touch outside the AI slot fails this immediately, so the
// other tabs keep their native behaviour too.
import OSLog
import SwiftUI
import UIKit

nonisolated private let log = Logger(subsystem: "com.luminavault", category: "quickassistant")

extension View {
    /// Runs `perform` when the AI tab is long-pressed. Apply it to the `TabView`.
    /// Does nothing on iPad, where the card has no trigger.
    ///
    /// While `coveredByModal` is true the tabs are hidden from VoiceOver. The tab
    /// controller's views are UIKit, so SwiftUI's `accessibilityHidden` does not
    /// reach them, and the card's modal trait cannot be relied on to either.
    @ViewBuilder
    func aiTabLongPress(
        coveredByModal: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self
        } else {
            background {
                AITabLongPressProbe(coveredByModal: coveredByModal, onFire: perform)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Marks this feature's recogniser, so a rebuilt probe can recognise one left on
/// the bar by the probe it replaces.
final class AITabLongPressRecognizer: UILongPressGestureRecognizer {}

@MainActor
final class AITabLongPressCoordinator: NSObject, UIGestureRecognizerDelegate {
    var onFire: (@MainActor () -> Void)?

    private lazy var recognizer: AITabLongPressRecognizer = {
        let recognizer = AITabLongPressRecognizer(target: self, action: #selector(fired))
        recognizer.minimumPressDuration = 0.4
        recognizer.delegate = self
        return recognizer
    }()

    func isAttached(to bar: UITabBar) -> Bool {
        recognizer.view === bar
    }

    /// Safe to call as often as SwiftUI updates the view. This coordinator has
    /// one recogniser, and a recogniser belongs to one view, so `addGestureRecognizer`
    /// moves it rather than copying it. Another probe's leftover is removed.
    func attach(to bar: UITabBar) {
        guard !isAttached(to: bar) else { return }
        for leftover in bar.gestureRecognizers ?? [] where leftover is AITabLongPressRecognizer {
            bar.removeGestureRecognizer(leftover)
        }
        bar.addGestureRecognizer(recognizer)
    }

    func detach() {
        recognizer.view?.removeGestureRecognizer(recognizer)
    }

    @objc private func fired(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onFire?()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let bar = recognizer.view else { return false }
        return AITabHitTest.isAITab(
            x: touch.location(in: bar).x,
            barWidth: bar.bounds.width,
            tabCount: MainTabView.AppTab.allCases.count,
            aiIndex: MainTabView.AppTab.allCases.firstIndex(of: .think) ?? 0
        )
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// The bar's own gestures wait for this one. Scoped to the bar: a scroll view
    /// or any other gesture outside it answers false and is not delayed.
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        guard let bar = recognizer.view, let otherView = other.view else { return false }
        return otherView.isDescendant(of: bar)
    }
}

/// An invisible view behind the `TabView`, there to reach the window. It looks
/// for the bar again whenever it might have changed: moving to a window, a layout
/// pass (rotation changes its size) and every SwiftUI update (which include
/// scene phase changes, since `MainTabView` reads `scenePhase`). `attach` makes
/// the repeats harmless.
private struct AITabLongPressProbe: UIViewRepresentable {
    let coveredByModal: Bool
    let onFire: @MainActor () -> Void

    func makeCoordinator() -> AITabLongPressCoordinator {
        AITabLongPressCoordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        context.coordinator.onFire = onFire
        return ProbeView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.onFire = onFire
        view.coveredByModal = coveredByModal
        view.attachIfPossible()
    }

    static func dismantleUIView(_: ProbeView, coordinator: AITabLongPressCoordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var coveredByModal = false
        private let coordinator: AITabLongPressCoordinator
        private var retryTask: Task<Void, Never>?

        init(coordinator: AITabLongPressCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                retryTask?.cancel()
                retryTask = nil
            } else {
                attachIfPossible()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfPossible()
        }

        func attachIfPossible() {
            guard window != nil else { return }
            if let tabs = findTabBarController() {
                retryTask?.cancel()
                retryTask = nil
                attach(to: tabs)
            } else if retryTask == nil {
                // The tab controller may not be assembled yet.
                retryTask = Task { [weak self] in await self?.retry() }
            }
        }

        private func retry() async {
            for _ in 0 ..< 10 {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                if let tabs = findTabBarController() {
                    attach(to: tabs)
                    retryTask = nil
                    return
                }
            }
            log.warning("AI tab long-press not attached: no UITabBarController found")
            retryTask = nil
        }

        private func attach(to tabs: UITabBarController) {
            coordinator.attach(to: tabs.tabBar)
            tabs.view.accessibilityElementsHidden = coveredByModal
        }

        /// Walks down the public view controller tree from the window's root.
        /// The shell's is the only `TabView` in the app.
        private func findTabBarController() -> UITabBarController? {
            guard let root = window?.rootViewController else { return nil }
            var queue = [root]
            while !queue.isEmpty {
                let controller = queue.removeFirst()
                if let tabs = controller as? UITabBarController { return tabs }
                queue.append(contentsOf: controller.children)
                if let presented = controller.presentedViewController { queue.append(presented) }
            }
            return nil
        }
    }
}
