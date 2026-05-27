// LuminaVaultClient/LuminaVaultClient/Components/HermieMascotView.swift
import SwiftUI
import RiveRuntime

public enum HermieMascotState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case happy
    /// HER-179 — fires for ~3 seconds when an APNS digest is delivered
    /// in-app. Maps to the existing `.happy` Rive trigger until a
    /// dedicated celebrate animation ships in the .riv file.
    case celebrating

    /// Rive trigger name fired on the state machine. `.celebrating`
    /// re-uses `.happy` until artwork lands.
    var riveTrigger: String {
        switch self {
        case .celebrating: "happy"
        default: rawValue
        }
    }
}

public struct HermieMascotView: View {

    @Environment(\.lvPalette) private var palette

    public let state: HermieMascotState
    public var size: CGFloat = 220
    public var fallbackImageName: String = "Mascot"

    @State private var viewModel: RiveViewModel?

    private static let riveFileName = "hermie"
    private static let stateMachineName = "State Machine 1"

    public init(state: HermieMascotState, size: CGFloat = 220, fallbackImageName: String = "Mascot") {
        self.state = state
        self.size = size
        self.fallbackImageName = fallbackImageName
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
        .shadow(color: palette.primary.opacity(0.45), radius: 30)
        .shadow(color: palette.accent.opacity(0.20), radius: 50)
        .accessibilityLabel("Hermie mascot — \(state.rawValue)")
        .task { loadIfAvailable() }
        .onChange(of: state) { _, newValue in
            fire(state: newValue)
        }
    }

    private func loadIfAvailable() {
        guard viewModel == nil else { return }
        guard Bundle.main.url(forResource: Self.riveFileName, withExtension: "riv") != nil else {
            return
        }
        let vm = RiveViewModel(
            fileName: Self.riveFileName,
            stateMachineName: Self.stateMachineName
        )
        viewModel = vm
        fire(state: state)
    }

    private func fire(state: HermieMascotState) {
        guard let viewModel else { return }
        viewModel.triggerInput(state.riveTrigger)
    }
}

/// Premium futuristic glassmorphic header for LuminaVault primary screens.
public struct LuminaHeader: View {
    @Environment(\.lvPalette) private var palette
    
    public let title: String
    public var showMascot: Bool = true
    public var mascotState: HermieMascotState = .idle
    public var onMascotTap: (() -> Void)? = nil
    
    public init(title: String, showMascot: Bool = true, mascotState: HermieMascotState = .idle, onMascotTap: (() -> Void)? = nil) {
        self.title = title
        self.showMascot = showMascot
        self.mascotState = mascotState
        self.onMascotTap = onMascotTap
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Title
            Text(title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.glowPrimary, palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
            
            Spacer()
            
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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

public struct SciFiCardView: View {
    @Environment(\.lvPalette) private var palette
    
    public let icon: String
    public let title: String
    public let subtitle: String
    public let color: SwiftUI.Color?
    
    public init(icon: String, title: String, subtitle: String, color: SwiftUI.Color? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(color ?? palette.glowPrimary)
                .shadow(color: (color ?? palette.glowPrimary).opacity(0.6), radius: 8)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .lvGlassCard(cornerRadius: 24, intensity: 0.7)
    }
}
