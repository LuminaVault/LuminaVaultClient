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
    /// in-app. Maps to the existing `.happy` Rive trigger until a
    /// dedicated celebrate animation ships in the .riv file.
    case celebrating

    /// Value driven into the `state` number input on "State Machine 1".
    /// Must match the transition conditions authored in `hermie.riv`
    /// (see `Resources/Hermie/README.md`).
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

    @State private var viewModel: RiveViewModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let riveFileName = "hermie"
    private static let stateMachineName = "State Machine 1"
    private static let stateInput = "state"
    private static let isPlayingInput = "isPlaying"
    /// Below this point size the animation is unreadable and the Rive
    /// canvas is not worth its runtime cost; the static PNG renders instead.
    private static let animationSizeThreshold: CGFloat = 64

    public init(state: HermieMascotState, size: CGFloat = 220, fallbackImageName: String = "Mascot", animated: Bool = true) {
        self.state = state
        self.size = size
        self.fallbackImageName = fallbackImageName
        self.animated = animated
    }

    private var riveEligible: Bool { animated && size >= Self.animationSizeThreshold }

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
        .shadow(color: palette.primary.opacity(0.45), radius: 30)
        .shadow(color: palette.accent.opacity(0.20), radius: 50)
        .accessibilityLabel("Hermie mascot — \(state.rawValue)")
        .task { loadIfAvailable() }
        .onChange(of: state) { _, newValue in
            apply(state: newValue)
        }
        .onChange(of: reduceMotion) { _, _ in
            apply(state: state)
        }
        .onChange(of: scenePhase) { _, phase in
            setLive(phase == .active)
        }
        .onAppear { setLive(true) }
        .onDisappear { setLive(false) }
    }

    private func loadIfAvailable() {
        guard riveEligible, viewModel == nil else { return }
        guard let vm = RiveAssets.viewModel(
            named: Self.riveFileName,
            stateMachineName: Self.stateMachineName
        ) else { return }
        viewModel = vm
        apply(state: state)
    }

    private func apply(state: HermieMascotState) {
        guard let viewModel else { return }
        viewModel.setInput(Self.stateInput, value: state.stateValue)
        viewModel.setInput(Self.isPlayingInput, value: !reduceMotion)
        if reduceMotion { viewModel.pause() }
    }

    /// Pause the render loop whenever the view leaves the screen or the app
    /// leaves the foreground — offscreen Rive canvases must not burn CPU.
    private func setLive(_ live: Bool) {
        guard let viewModel else { return }
        if live && !reduceMotion {
            viewModel.play()
        } else {
            viewModel.pause()
        }
    }
}

/// Premium futuristic glassmorphic header for LuminaVault primary screens.
public struct LuminaHeader: View {
    @Environment(\.lvPalette) private var palette
    
    public let title: String
    public var showMascot: Bool = true
    /// HER-255 — when true, a compact "+" capture button is rendered in the
    /// header (left of the mascot), replacing the old floating FAB.
    public var showCapture: Bool = true
    public var mascotState: HermieMascotState = .idle
    public var onMascotTap: (() -> Void)? = nil

    public init(title: String, showMascot: Bool = true, showCapture: Bool = true, mascotState: HermieMascotState = .idle, onMascotTap: (() -> Void)? = nil) {
        self.title = title
        self.showMascot = showMascot
        self.showCapture = showCapture
        self.mascotState = mascotState
        self.onMascotTap = onMascotTap
    }
    
    public var body: some View {
        HStack(spacing: LVSpacing.md) {
            // Title
            Text(title)
                .font(LVTypography.display.font.weight(.black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.glowPrimary, palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
            
            Spacer()

            // HER-255 — compact capture "+" lives in the header now (was a
            // floating FAB over the tab bar). Sits left of the mascot avatar.
            if showCapture {
                CaptureFAB(style: .header)
            }

            // Mascot Avatar
            if showMascot {
                Button {
                    onMascotTap?()
                } label: {
                    HermieMascotView(state: mascotState, size: 38, fallbackImageName: "OnboardingMascot")
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [palette.glowPrimary.opacity(0.8), palette.accent.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                        .shadow(color: palette.glowPrimary.opacity(0.7), radius: 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.base)
        .background {
            // Glass background
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            // Glowing bottom border
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [SwiftUI.Color.clear, palette.glowPrimary.opacity(0.4), SwiftUI.Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
