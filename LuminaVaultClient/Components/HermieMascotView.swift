// LuminaVaultClient/LuminaVaultClient/Components/HermieMascotView.swift
import SwiftUI
import RiveRuntime

enum HermieMascotState: String, CaseIterable, Sendable {
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

struct HermieMascotView: View {
    let state: HermieMascotState
    var size: CGFloat = 220
    var fallbackImageName: String = "Mascot"

    @State private var viewModel: RiveViewModel?

    private static let riveFileName = "hermie"
    private static let stateMachineName = "State Machine 1"

    var body: some View {
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
        .shadow(color: Color.lvCyan.opacity(0.45), radius: 30)
        .shadow(color: Color.lvAmber.opacity(0.20), radius: 50)
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

#Preview("Idle") {
    HermieMascotView(state: .idle)
        .lvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

#Preview("Thinking") {
    HermieMascotView(state: .thinking)
        .lvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

#Preview("Happy") {
    HermieMascotView(state: .happy)
        .lvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
