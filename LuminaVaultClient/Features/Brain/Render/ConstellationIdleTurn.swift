// When the Constellation's idle turn may run, how often it steps and how far.
// Pure; `BrainGraphRealityView` consults it on every step.

import Foundation

/// The slow turn of an untouched sky. It runs only with nothing selected, the
/// app in the foreground, no sheet over it, Reduce Motion off and no finger down, after 5 s without a
/// touch; steps at most 30 times a second; and stops for good (until the next
/// touch) after 90 s.
nonisolated enum ConstellationIdleTurn {
    static let idleDelay: Duration = .seconds(5)
    /// One step per thirtieth of a second at most.
    static let maxStepsPerSecond = 30
    static let stepInterval: Duration = .microseconds(1_000_000 / maxStepsPerSecond + 1)
    static let maxTurn: Duration = .seconds(90)
    /// One revolution per three minutes.
    static let radiansPerSecond: Double = 2 * .pi / 180
    /// While turning, labels are re-chosen this often.
    static let rerankInterval: Duration = .seconds(2)

    nonisolated struct State: Equatable, Sendable {
        var selected: Int
        var idle: Duration
        /// The app is in the foreground.
        var visible: Bool
        /// A sheet covers the screen.
        var covered = false
        var reduceMotion: Bool
        var pressing: Bool
        /// How long this turn has run so far.
        var turned: Duration = .zero
    }

    /// Whether the turn may start, or take its next step. Asked on every step.
    static func allowed(_ s: State) -> Bool {
        s.selected == 0 && s.idle >= idleDelay && s.visible && !s.covered && !s.reduceMotion && !s.pressing
            && continues(turned: s.turned)
    }

    /// Whether a turn that has run for `turned` may take another step.
    static func continues(turned: Duration, max: Duration = maxTurn) -> Bool {
        turned < max
    }

    /// How far a step after `elapsed` turns.
    static func angle(after elapsed: Duration) -> Double {
        let c = elapsed.components
        return radiansPerSecond * (Double(c.seconds) + Double(c.attoseconds) / 1e18)
    }
}
