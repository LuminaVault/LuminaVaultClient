// LuminaVaultClient/LuminaVaultClient/Components/HermieMotion.swift
//
// Hermie's seven reactions, as maths rather than as an artboard.
//
// There is no `.riv` file in this repository — `Resources/Hermie/` holds a
// `.gitkeep` and a design brief, nothing else — so every `HermieMascotView`
// on screen is rendering its PNG fallback. Seven distinct states were being
// driven into a `state` number input that nothing reads, and all seven looked
// identical. This file is the host-side answer: the same choreography the
// brief describes (`Resources/Hermie/README.md`), expressed as transforms on
// the fallback image. See `Resources/README_RIVE.md` for why this is the
// deliberate interim rather than a workaround.
//
// # Shape of the thing
//
// Every reaction is a pure function of one scalar, `cycle` ∈ [0, 1]:
//
//     pose = HermieMotion.pose(for: state, cycle: cycle, size: size)
//
// `HermieMotionModifier` animates `cycle` (it is the modifier's
// `animatableData`, so the pose is recomputed per frame) and the view drives
// it 0 → 1, looping for the ambient states and once for the one-shots.
//
// # The invariant that protects twelve snapshot baselines
//
// **Every curve below is zero at `cycle == 0` and at `cycle == 1`**, so every
// pose at the loop seam is exactly `HermiePose.identity` — no scale, no
// rotation, no offset, no opacity or glow change. Combined with
// `plan(...) == .still` whenever `\.accessibilityReduceMotion` is on or
// `\.lvAmbientMotionEnabled` is off (at which point `HermieMotionModifier`
// applies *no transform modifiers at all*), the frozen frame is bit-for-bit
// the frame that rendered before any of this existed. `HermieMotionTests`
// pins both halves of that claim.
//
// Pure and view-free on purpose, exactly like `HermieMascotPlayback`: the
// decision "does this state animate, in which way, at this size, under these
// accessibility settings" is testable without a view, a renderer or Rive.
//
// All seven states get a reaction, including the two the guided start can
// never reach (`sleeping`, `sad` — see `GuidedStartCoordinator.hermieState`).
// Other features drive those, and an incomplete set would be a trap for
// whoever adds the next caller.

import CoreGraphics
import Foundation

// MARK: - Pose

/// One frame of Hermie: what to multiply, rotate, shift and dim by.
///
/// Travel is stored as a *ratio of the rendered size* rather than in points,
/// so the same reaction reads the same at a 96pt avatar and a 220pt hero
/// instead of turning into a twitch at the small end.
struct HermiePose: Equatable {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// Degrees, about the mascot's feet (`anchor: .bottom`).
    var rotationDegrees: Double = 0
    /// Multiplied by the view's `size` to get points. Negative is upward.
    var offsetYRatio: CGFloat = 0
    var opacity: Double = 1
    /// Multiplier on the two palette shadows the view already applies.
    /// `1` reproduces today's `0.45` / `0.20` opacities exactly.
    var glow: Double = 1

    /// The resting pose, and the *only* pose a frozen mascot can be in.
    static let identity = HermiePose()

    var isIdentity: Bool { self == .identity }

    func offsetY(for size: CGFloat) -> CGFloat { offsetYRatio * size }
}

// MARK: - Plan

/// What a given state does at a given size under the current settings.
enum HermieMotionPlan: Equatable {
    /// No host-side motion at all. The mascot renders exactly as the static
    /// image does today.
    case still
    /// Ambient: runs continuously while the view is live. `period` seconds
    /// per cycle, driven linearly — the shape lives in the pose function, so
    /// an eased carrier would stutter at the seam.
    case loop(HermieMascotState, period: Double)
    /// A reaction: plays once and settles back to rest.
    case oneShot(HermieMascotState, duration: Double)

    var isStill: Bool { self == .still }

    /// Seconds for one traversal of `cycle` 0 → 1, or `nil` when still.
    var duration: Double? {
        switch self {
        case .still: nil
        case .loop(_, let period): period
        case .oneShot(_, let duration): duration
        }
    }

    var isLooping: Bool {
        if case .loop = self { return true }
        return false
    }

    func pose(at cycle: Double, size: CGFloat) -> HermiePose {
        switch self {
        case .still:
            return .identity
        case .loop(let state, _), .oneShot(let state, _):
            return HermieMotion.pose(for: state, cycle: cycle, size: size)
        }
    }
}

// MARK: - Choreography

enum HermieMotion {

    /// Below this rendered size the host-side motion is not worth having.
    ///
    /// **48, deliberately below the Rive canvas's own 64pt bar** (see
    /// `HermieMascotView.riveSizeThreshold`) — the two thresholds answer
    /// different questions. A Rive canvas has a per-instance runtime cost, so
    /// "is this worth a render loop" is a high bar. Four affine transforms
    /// cost nothing, so the only question here is "does it read", and at
    /// 56pt a 4.5° sway moves the top of Hermie's head four points, which
    /// plainly does.
    ///
    /// 48 is where it lands because the two things that matter sit either
    /// side of it. Below: the 32pt mascots in the chat transcript, where
    /// dozens of simultaneous loops would be real CPU for motion nobody can
    /// see. Above: the 56pt avatars in the guided-start card and the
    /// spotlight bubble — the two places in the app where Hermie is most
    /// obviously supposed to be doing something, and, before this, the two
    /// places he was completely inert.
    ///
    /// The container still reacts on top: both cards bump the mascot 1.08×
    /// on `happy` / `celebrating`. That bump and this motion compose.
    static let sizeThreshold: CGFloat = 48

    // MARK: Tempos
    //
    // Choreography, not design tokens: these are Hermie's tempos, taken from
    // the timeline table in `Resources/Hermie/README.md` and matched
    // state-for-state with the web implementation, so the two platforms read
    // as one character. The eventual artboard inherits the same rhythm. The
    // *carrier* they ride is `LVMotion.cycle(duration:)`.

    /// 3.0 s — slow, shallow breathing.
    static let idlePeriod = 3.0
    /// 1.6 s — one full pendulum swing, left through right and back.
    static let thinkingPeriod = 1.6
    /// 4.0 s — slower than idle, because a slump should not look busy.
    static let sadPeriod = 4.0
    /// 4.5 s — the slowest loop; deep breathing.
    static let sleepingPeriod = 4.5
    /// 1.2 s — the fastest loop; an absorb pulse should read as working.
    static let learningPeriod = 1.2
    /// 2.0 s — squash, stretch, rise, land. Long for a hop, and that is the
    /// number both the design brief and web use; the linear carrier keeps the
    /// weight in the right place rather than letting it drift.
    static let happyDuration = 2.0
    /// 0.9 s — two hops and a wiggle.
    static let celebratingDuration = 0.9

    /// The whole decision: does this state animate, in which way, at this
    /// size, under these accessibility settings.
    ///
    /// - reduceMotion: `\.accessibilityReduceMotion`; always wins. A
    ///   `repeatForever` has no meaningful cross-fade equivalent, so the
    ///   right degradation is the one `View.lvRepeatingAnimation` prescribes
    ///   — settle at rest and stay there — rather than a substituted curve.
    /// - ambientMotionEnabled: `\.lvAmbientMotionEnabled`. Production never
    ///   sets it; snapshot suites set it false and expect the frozen frame.
    static func plan(
        for state: HermieMascotState,
        size: CGFloat,
        reduceMotion: Bool,
        ambientMotionEnabled: Bool
    ) -> HermieMotionPlan {
        guard !reduceMotion, ambientMotionEnabled, size >= sizeThreshold else {
            return .still
        }
        switch state {
        case .idle: return .loop(.idle, period: idlePeriod)
        case .thinking: return .loop(.thinking, period: thinkingPeriod)
        case .sad: return .loop(.sad, period: sadPeriod)
        case .sleeping: return .loop(.sleeping, period: sleepingPeriod)
        case .learning: return .loop(.learning, period: learningPeriod)
        case .happy: return .oneShot(.happy, duration: happyDuration)
        case .celebrating: return .oneShot(.celebrating, duration: celebratingDuration)
        }
    }

    // MARK: - Curves
    //
    // All four are zero at cycle 0 and cycle 1. That is the whole frozen-frame
    // guarantee — no pose below can deviate from identity at the seam because
    // every term it is built from vanishes there.

    /// 0 → 1 → 0. A breath: in on the first half, out on the second.
    static func breath(_ cycle: Double) -> Double {
        (1 - cos(2 * .pi * cycle)) / 2
    }

    /// 0 → +1 → 0 → −1 → 0. One symmetric pendulum swing per cycle.
    static func swing(_ cycle: Double) -> Double {
        sin(2 * .pi * cycle)
    }

    /// 0 → 1 → 0. A single arc — one hop.
    static func arc(_ cycle: Double) -> Double {
        sin(.pi * cycle)
    }

    /// Two arcs per cycle — a double hop, both feet back on the floor at the
    /// end.
    static func hops(_ cycle: Double) -> Double {
        abs(sin(2 * .pi * cycle))
    }

    /// Two full swings per cycle — the wiggle that rides the double hop.
    static func wiggle(_ cycle: Double) -> Double {
        sin(4 * .pi * cycle)
    }

    // MARK: - The table
    //
    // `size` is unused today: every amplitude is already a ratio or an angle,
    // which is what makes a reaction size-independent. It stays in the
    // signature because the pose is the one place a size-dependent term (a
    // point-quantised bob, say) would belong.

    /// The pose for `state` at `cycle`. Pure; `cycle` outside [0, 1] simply
    /// continues the periodic curves, which is what a loop wants.
    static func pose(for state: HermieMascotState, cycle: Double, size: CGFloat) -> HermiePose {
        switch state {
        case .idle: return idlePose(cycle)
        case .thinking: return thinkingPose(cycle)
        case .happy: return happyPose(cycle)
        case .sad: return sadPose(cycle)
        case .sleeping: return sleepingPose(cycle)
        case .learning: return learningPose(cycle)
        case .celebrating: return celebratingPose(cycle)
        }
    }

    /// Breathing. Rises and swells a little, brightens a little, ticks a
    /// degree either way. Deliberately the least eventful thing here — it is
    /// what Hermie does when nothing is happening.
    private static func idlePose(_ cycle: Double) -> HermiePose {
        let b = breath(cycle)
        return HermiePose(
            scaleX: 1 - 0.010 * b,
            scaleY: 1 + 0.028 * b,
            rotationDegrees: 0.9 * swing(cycle),
            offsetYRatio: -0.016 * b,
            glow: 1 + 0.10 * b
        )
    }

    /// Pendulum. A full ±4.5° sway about the feet with a small lift and a
    /// glow pulse — the only state that travels sideways, which is what makes
    /// it readable at a glance next to `idle`.
    private static func thinkingPose(_ cycle: Double) -> HermiePose {
        let b = breath(cycle)
        return HermiePose(
            rotationDegrees: 4.5 * swing(cycle),
            offsetYRatio: -0.012 * b,
            glow: 1 + 0.30 * b
        )
    }

    /// One hop: stretch into the rise, squash into the landing, bright at the
    /// apex. Plays once and settles — a completion is an event, not a mood.
    private static func happyPose(_ cycle: Double) -> HermiePose {
        let a = arc(cycle)
        let s = swing(cycle)
        return HermiePose(
            scaleX: 1 - 0.07 * s,
            scaleY: 1 + 0.09 * s,
            offsetYRatio: -0.11 * a,
            glow: 1 + 0.45 * a
        )
    }

    /// Slump. Tips over, sinks, shrinks, fades, and the glow all but goes
    /// out. The only state that loses light, which is what distinguishes it
    /// from `sleeping` at a glance.
    private static func sadPose(_ cycle: Double) -> HermiePose {
        let b = breath(cycle)
        return HermiePose(
            scaleX: 1 - 0.025 * b,
            scaleY: 1 - 0.025 * b,
            rotationDegrees: 3.5 * b,
            offsetYRatio: 0.022 * b,
            opacity: 1 - 0.14 * b,
            glow: 1 - 0.65 * b
        )
    }

    /// Deep, slow breathing with a lean. Twice idle's amplitude at half its
    /// tempo, sinking rather than lifting, dimming rather than brightening:
    /// the same gesture as idle, read in the opposite direction.
    private static func sleepingPose(_ cycle: Double) -> HermiePose {
        let b = breath(cycle)
        return HermiePose(
            scaleX: 1 + 0.030 * b,
            scaleY: 1 + 0.055 * b,
            rotationDegrees: -3.0 * b,
            offsetYRatio: 0.012 * b,
            opacity: 1 - 0.06 * b,
            glow: 1 - 0.45 * b
        )
    }

    /// Absorb pulse. Uniform swell and a hard glow ramp on the fastest loop
    /// here — no travel, no tilt, so it reads as intake rather than movement.
    private static func learningPose(_ cycle: Double) -> HermiePose {
        let b = breath(cycle)
        return HermiePose(
            scaleX: 1 + 0.05 * b,
            scaleY: 1 + 0.05 * b,
            glow: 1 + 0.85 * b
        )
    }

    /// Double hop with a wiggle — two rises, two full ±6° swings, swelling
    /// and flaring on each. The largest excursion in the set, because it is
    /// the one that fires once at the end of the guided start and has to be
    /// unmistakable.
    private static func celebratingPose(_ cycle: Double) -> HermiePose {
        let h = hops(cycle)
        return HermiePose(
            scaleX: 1 + 0.06 * h,
            scaleY: 1 + 0.06 * h,
            rotationDegrees: 6.0 * wiggle(cycle),
            offsetYRatio: -0.085 * h,
            glow: 1 + 0.60 * h
        )
    }
}
