// LuminaVaultClient/LuminaVaultClient/Components/HermieMascotView.swift
import SwiftUI
import RiveRuntime

public enum HermieMascotState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case happy
    /// HER-152 — mascot dims/slumps when a capture or kb-compile fails.
    case sad
    /// HER-152 — idle-timeout state; mascot drifts to sleep after the
    /// app sits untouched. Driven from the app's inactivity timer.
    case sleeping
    /// HER-152 — pulses while a kb-compile / embedding job runs so the
    /// mascot reads as "absorbing" the new memo.
    case learning
    /// HER-179 — fires for ~3 seconds when an APNS digest is delivered
    /// in-app, and once at the end of the guided start.
    case celebrating

    /// Value driven into the `state` number input on "State Machine 1".
    /// Must match the transition conditions the eventual `hermie` artboard
    /// authors (see `Resources/Hermie/README.md`). No `.riv` file exists yet,
    /// so today every one of these is a no-op and the reaction the user
    /// actually sees is the host-side one in `HermieMotion` — which is the
    /// point of sending them anyway: the artboard lands without a code
    /// change here. `Resources/README_RIVE.md` has the full state of play.
    var stateValue: Double {
        switch self {
        case .idle: 0
        case .thinking: 1
        case .happy: 2
        case .sad: 3
        case .sleeping: 4
        case .learning: 5
        case .celebrating: 6
        }
    }
}

public struct HermieMascotView: View {

    @Environment(\.lvPalette) private var palette

    public let state: HermieMascotState
    public var size: CGFloat = 220
    public var fallbackImageName: String = "Mascot"
    /// Call-site opt-out from the Rive canvas. Small avatars skip Rive
    /// regardless — dozens of live instances in a chat list is real CPU.
    public var animated: Bool = true
    /// When set, Rive only plays while `lvActiveTab` matches (TabView keeps
    /// sibling tabs mounted, so `onDisappear` alone is insufficient).
    public var hostTab: String? = nil

    @State private var viewModel: RiveViewModel?

    /// The single animated scalar behind every host-side reaction. Every pose
    /// is a pure function of it (`HermieMotion.pose(for:cycle:size:)`) and
    /// `cycle == 0` is the resting pose for all seven states, so "stop
    /// moving" is exactly "snap this back to 0".
    @State private var cycle: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lvActiveTab) private var activeTab
    /// Snapshot suites set this false to hold one frame — of the Rive state
    /// machine when one is loaded, and of the host-side motion below when it
    /// is not. Without it the state machine kept animating under test and
    /// `think-empty-dark` captured a different frame on different CI runs.
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotionEnabled

    private static let riveFileName = "lumina_anims"
    private static let artboardName = "hermie"
    private static let stateMachineName = "State Machine 1"
    private static let stateInput = "state"
    private static let isPlayingInput = "isPlaying"
    /// Below this point size a Rive canvas is not worth its runtime cost —
    /// dozens of live instances in a chat list is real CPU — so the static
    /// PNG renders instead. Higher than `HermieMotion.sizeThreshold` on
    /// purpose: four affine transforms cost nothing, a render loop does.
    private static let riveSizeThreshold: CGFloat = 64

    public init(
        state: HermieMascotState,
        size: CGFloat = 220,
        fallbackImageName: String = "Mascot",
        animated: Bool = true,
        hostTab: String? = nil
    ) {
        self.state = state
        self.size = size
        self.fallbackImageName = fallbackImageName
        self.animated = animated
        self.hostTab = hostTab
    }

    private var riveEligible: Bool { animated && size >= Self.riveSizeThreshold }

    private var shouldPlay: Bool {
        HermieMascotPlayback.shouldPlay(
            reduceMotion: reduceMotion,
            ambientMotionEnabled: ambientMotionEnabled,
            sceneActive: scenePhase == .active,
            hostTab: hostTab,
            activeTab: activeTab
        )
    }

    /// Motion the state machine itself may run, independent of visibility.
    private var motionAllowed: Bool { !reduceMotion && ambientMotionEnabled }

    /// What the *fallback* image does for this state. `.still` whenever
    /// Reduce Motion is on, `\.lvAmbientMotionEnabled` is off, the call site
    /// opted out, or the mascot is too small for the motion to read — and
    /// `.still` means `HermieMotionModifier` applies no transform at all.
    ///
    /// `animated` is folded in here as well as into `riveEligible`: a call
    /// site that opted out of the Rive canvas is opting out of motion, not
    /// merely out of Rive.
    private var motionPlan: HermieMotionPlan {
        guard animated else { return .still }
        return HermieMotion.plan(
            for: state,
            size: size,
            reduceMotion: reduceMotion,
            ambientMotionEnabled: ambientMotionEnabled
        )
    }

    /// Everything the host-side driver depends on. `.task(id:)` restarts on
    /// any change and is torn down when the view goes away.
    private var motionKey: MotionKey { MotionKey(plan: motionPlan, live: shouldPlay) }

    private struct MotionKey: Equatable {
        let plan: HermieMotionPlan
        let live: Bool
    }

    public var body: some View {
        Group {
            if let viewModel {
                viewModel.view()
                    .frame(width: size, height: size)
            } else {
                Image(fallbackImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        }
        // Owns the two palette shadows as well as the transforms, because
        // `learning` and `sad` express themselves partly through the glow.
        // In the `.still` branch it applies those shadows and nothing else,
        // at exactly the opacities this view used before it could move.
        .modifier(HermieMotionModifier(plan: motionPlan, size: size, cycle: cycle))
        .accessibilityLabel("Hermie mascot — \(state.rawValue)")
        .task { loadIfAvailable() }
        .task(id: motionKey) { await driveHostMotion() }
        .onChange(of: state) { _, newValue in
            apply(state: newValue)
        }
        .onChange(of: reduceMotion) { _, _ in
            apply(state: state)
        }
        .onChange(of: ambientMotionEnabled) { _, _ in
            apply(state: state)
        }
        .onChange(of: scenePhase) { _, _ in
            setLive(shouldPlay)
        }
        .onChange(of: activeTab) { _, _ in
            setLive(shouldPlay)
        }
        .onAppear { setLive(shouldPlay) }
        .onDisappear {
            setLive(false)
            // `.task(id:)` is cancelled here, but a `repeatForever` already
            // handed to the render server is not — it has to be revoked by
            // writing the value back. Same reason `\.lvAmbientMotionEnabled`
            // exists at all.
            stopHostMotion()
        }
    }

    private func loadIfAvailable() {
        guard riveEligible, viewModel == nil else { return }
        guard let vm = RiveAssets.viewModel(
            named: Self.riveFileName,
            artboardName: Self.artboardName,
            stateMachineName: Self.stateMachineName
        ) else { return }
        viewModel = vm
        apply(state: state)
        // `onAppear` already ran, and it found no view model to pause — a
        // mascot mounted on an inactive tab or in the background would
        // otherwise start playing the moment the file loaded.
        setLive(shouldPlay)
    }

    private func apply(state: HermieMascotState) {
        guard let viewModel else { return }
        viewModel.setInput(Self.stateInput, value: state.stateValue)
        viewModel.setInput(Self.isPlayingInput, value: motionAllowed)
        if !motionAllowed { viewModel.pause() }
    }

    /// Pause the render loop whenever the view leaves the screen or the app
    /// leaves the foreground — offscreen Rive canvases must not burn CPU.
    private func setLive(_ live: Bool) {
        guard let viewModel else { return }
        if live && motionAllowed {
            viewModel.play()
        } else {
            viewModel.pause()
        }
    }

    // MARK: - Host-side motion

    /// Runs the fallback image's reaction. The same discipline the Rive path
    /// gets: nothing is scheduled unless the plan says to move *and* the view
    /// is on screen, in the foreground, on the active tab.
    private func driveHostMotion() async {
        stopHostMotion()
        guard shouldPlay, let duration = motionPlan.duration else { return }
        // `stopHostMotion` lands in this update. The cycle has to start in a
        // later one, or SwiftUI sees the stored value go 1 → 0 → 1 inside a
        // single transaction, concludes nothing changed, and animates
        // nothing. Cancellation (disappear, state change) falls out here.
        guard (try? await Task.sleep(for: .milliseconds(16))) != nil else { return }
        let carrier = LVMotion.cycle(duration: duration)
        withAnimation(motionPlan.isLooping ? carrier.repeatForever(autoreverses: false) : carrier) {
            cycle = 1
        }
    }

    /// Revoke any running animation and hold the resting pose. Unanimated on
    /// purpose: this is the frame every state agrees on.
    ///
    /// Not routed through `lvAnimation` / `LVMotion.reduced`: a
    /// `repeatForever` has no cross-fade equivalent, so the Reduce Motion
    /// degradation here is the one `View.lvRepeatingAnimation` documents —
    /// settle at rest and stay there — and it is enforced a step earlier, by
    /// `HermieMotion.plan` returning `.still`.
    private func stopHostMotion() {
        guard cycle != 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { cycle = 0 }
    }
}

// MARK: - Motion modifier

/// Applies a `HermiePose` to the mascot, recomputing it per frame from the
/// animated `cycle`.
///
/// `Animatable` is what makes the sinusoids in `HermieMotion` work at all:
/// SwiftUI interpolates a modifier's `animatableData` and calls `body` for
/// each intermediate value, so a pose that is a non-linear function of the
/// cycle is honoured frame by frame. Animating the transforms directly would
/// interpolate endpoint-to-endpoint instead, and a loop whose endpoints are
/// both the resting pose would render as no motion at all.
private struct HermieMotionModifier: ViewModifier, Animatable {
    @Environment(\.lvPalette) private var palette

    let plan: HermieMotionPlan
    let size: CGFloat
    var cycle: Double

    var animatableData: Double {
        get { cycle }
        set { cycle = newValue }
    }

    private var pose: HermiePose { plan.pose(at: cycle, size: size) }

    @ViewBuilder
    func body(content: Content) -> some View {
        if plan.isStill {
            // The frozen frame, and byte-for-byte what this view rendered
            // before it could move: the two shadows, no transform, no
            // opacity change. The branch is keyed on `plan`, not on the
            // per-frame pose, so it never flips mid-animation.
            content
                .shadow(color: palette.primary.opacity(0.45), radius: 30)
                .shadow(color: palette.accent.opacity(0.20), radius: 50)
        } else {
            content
                .shadow(color: palette.primary.opacity(0.45 * pose.glow), radius: 30)
                .shadow(color: palette.accent.opacity(0.20 * pose.glow), radius: 50)
                // Anchored at the feet: a mascot sways and squashes about the
                // ground it stands on, not about its middle.
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(pose.rotationDegrees), anchor: .bottom)
                .offset(y: pose.offsetY(for: size))
                .opacity(pose.opacity)
        }
    }
}

// HER-304 — SciFiCardView is single-module only (used by Home + Reflect).
// Dropped the `public` decoration so the new LVIcon-token init can stay
// internal-scope alongside its parameter type.
struct SciFiCardView: View {
    @Environment(\.lvPalette) private var palette

    /// HER-304 — icon resolution. `.sfSymbol(_)` keeps the legacy path
    /// (Reflect feature still passes raw SF Symbol strings). `.token(_)`
    /// renders through `LVIconView` so any `LVIcon` case with a
    /// `customAssetName` picks up its branded glyph for free.
    enum IconKind {
        case sfSymbol(String)
        case token(LVIcon)
    }

    let iconKind: IconKind
    let title: String
    let subtitle: String
    let color: SwiftUI.Color?

    init(icon: String, title: String, subtitle: String, color: SwiftUI.Color? = nil) {
        self.iconKind = .sfSymbol(icon)
        self.title = title
        self.subtitle = subtitle
        self.color = color
    }

    /// HER-304 — preferred init. Pass an `LVIcon` token; the view picks up
    /// the branded `Lumina/Icons/*` PNG (HER-301) when one exists,
    /// otherwise falls back to the token's SF Symbol.
    init(icon: LVIcon, title: String, subtitle: String, color: SwiftUI.Color? = nil) {
        self.iconKind = .token(icon)
        self.title = title
        self.subtitle = subtitle
        self.color = color
    }

    var body: some View {
        VStack(spacing: LVSpacing.md) {
            iconView
                .shadow(color: (color ?? palette.glowPrimary).opacity(0.6), radius: 8)

            VStack(spacing: LVSpacing.xs) {
                Text(title)
                    .font(LVTypography.fieldLabel.font.weight(.bold))
                    .foregroundStyle(palette.textPrimary)

                Text(subtitle)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, LVSpacing.lg)
        .padding(.horizontal, LVSpacing.md)
        .frame(maxWidth: .infinity)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.7)
    }

    @ViewBuilder
    private var iconView: some View {
        switch iconKind {
        case .sfSymbol(let name):
            // HER-291: kept as Image — runtime symbol name
            Image(systemName: name)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(color ?? palette.glowPrimary)
        case .token(let icon):
            LVIconView(icon, size: 32, tint: color ?? palette.glowPrimary, weight: .light)
        }
    }
}
