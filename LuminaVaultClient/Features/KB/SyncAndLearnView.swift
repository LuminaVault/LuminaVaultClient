// LuminaVaultClient/LuminaVaultClient/Features/KB/SyncAndLearnView.swift
// HER-36: home-tab "Sync & Learn" panel. Replaces the static mascot/title
// screen with a one-tap kb-compile CTA, Hermie mascot animation, and a
// terse status line under the button.
import SwiftUI

struct SyncAndLearnView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: SyncAndLearnViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()

                HermieMascotView(state: vm.mascotState, size: 220, fallbackImageName: "OnboardingMascot")

                Text("Sync & Learn")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [palette.accent, palette.primary],
                        startPoint: .leading, endPoint: .trailing,
                    ))

                Text(captionText)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(minHeight: 36, alignment: .top)

                Spacer()

                LVButton("Sync & Learn", isLoading: vm.isBusy) {
                    Task { await vm.sync() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .disabled(vm.isBusy)
            }
        }
        .lvBackground()
    }

    private var captionText: String {
        switch vm.phase {
        case .idle:
            "Compile new captures into your memory."
        case .syncing:
            "Compiling… this can take a moment."
        case .done(let count, _):
            count == 0
                ? "Nothing new to learn — try capturing first."
                : "Synced \(count) memor\(count == 1 ? "y" : "ies")."
        case .queued:
            "Saved locally — will sync when online."
        case .failed(let message):
            "Couldn't sync: \(message)"
        }
    }
}
