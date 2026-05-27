// LuminaVaultClient/LuminaVaultClient/Features/KB/SyncAndLearnView.swift
// HER-108 — home-tab "Sync & Learn" surface. Replaces the static caption
// with live progress microcopy (HER-288), disable-on-zero (HER-293),
// confetti on completion, and memory review sheet (HER-290).
import LuminaVaultShared
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

                LVButton(buttonLabel, isLoading: vm.isBusy) {
                    Task { await vm.sync() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .disabled(vm.isDisabled)
            }
            .overlay(ConfettiOverlay(trigger: vm.confettiTrigger))
        }
        .lvBackground()
        .task {
            await vm.refreshPending()
        }
        .sheet(isPresented: reviewSheetBinding) {
            MemoryReviewSheet(
                memories: vm.savedMemories,
                onApprove: { memory in await vm.approve(memory) },
                onReject: { memory in await vm.reject(memory) },
                onDismiss: { vm.dismissReview() },
            )
        }
    }

    private var reviewSheetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .reviewing = vm.phase { return true }
                return false
            },
            set: { newValue in
                if !newValue, case .reviewing = vm.phase {
                    vm.dismissReview()
                }
            },
        )
    }

    private var buttonLabel: String {
        switch vm.phase {
        case .reviewing: "Reviewing…"
        case .done: "Done"
        default:
            vm.pendingFiles == 0
                ? "Nothing to sync"
                : "Sync & Learn (\(vm.pendingFiles))"
        }
    }

    private var captionText: String {
        switch vm.phase {
        case .idle:
            vm.pendingFiles == 0
                ? "Nothing new to learn — try capturing first."
                : "\(vm.pendingFiles) new \(vm.pendingFiles == 1 ? "note" : "notes") ready to compile."
        case .syncing:
            progressCaption
        case .reviewing:
            "Review what Hermes learned."
        case .done(let count):
            count == 0
                ? "Nothing new to learn — try capturing first."
                : "Synced \(count) memor\(count == 1 ? "y" : "ies")."
        case .queued:
            "Saved locally — will sync when online."
        case .failed(let message):
            "Couldn't sync: \(message)"
        }
    }

    private var progressCaption: String {
        guard let event = vm.lastProgressEvent else {
            return "Compiling… this can take a moment."
        }
        switch event {
        case .started(let payload):
            return payload.totalFiles == 0
                ? "Nothing new to learn — try capturing first."
                : "Reading \(payload.totalFiles) note\(payload.totalFiles == 1 ? "" : "s")…"
        case .preparing:
            return "Preparing your notes…"
        case .thinking:
            let saved = vm.savedMemories.count
            return saved == 0
                ? "Hermes is thinking…"
                : "Saved \(saved) memor\(saved == 1 ? "y" : "ies") so far…"
        case .memorySaved:
            return "Saved \(vm.savedMemories.count) memor\(vm.savedMemories.count == 1 ? "y" : "ies") so far…"
        case .completed(let payload):
            return "Synced \(payload.response.memoriesIngested) memor\(payload.response.memoriesIngested == 1 ? "y" : "ies")."
        case .error(let payload):
            return "Couldn't sync: \(payload.message)"
        }
    }
}
