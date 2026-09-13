// LuminaVaultClient/LuminaVaultClient/Features/Home/CaptureHomeView.swift
//
// Home is capture.
//
// This tab used to open on the dashboard, which meant the first thing a new
// user saw was a report about a vault they had not filled yet. The vault is
// the product; putting something in it is the thing to make effortless. The
// dashboard keeps everything it had and moved behind the tab bar's More menu.

import SwiftUI
import LuminaVaultShared

struct CaptureHomeView: View {
    @Environment(\.lvPalette) private var palette

    @State private var vm: CaptureHomeViewModel
    @FocusState private var composerFocused: Bool
    @State private var sheetPresented = false
    @State private var sheetMode: CaptureSheet.Mode = .photo

    private let vaultClient: VaultClientProtocol
    private let memoryClient: MemoryClientProtocol
    /// Takes the user to the dashboard this tab used to be.
    private let onOpenDashboard: () -> Void

    init(
        vm: CaptureHomeViewModel,
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryClientProtocol,
        onOpenDashboard: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: vm)
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.onOpenDashboard = onOpenDashboard
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LVSpacing.lg) {
                if let toast = vm.toast {
                    statusBanner(toast)
                }

                HomeComposer(
                    text: $vm.text,
                    focused: $composerFocused,
                    isSaving: vm.saving,
                    detectedLink: vm.detectedLink,
                    canSave: vm.canSave,
                    isRecording: vm.isRecording,
                    recordingElapsed: vm.recorder.elapsed,
                    spaces: vm.availableSpaces ?? [],
                    selectedSpaceID: $vm.selectedSpaceID,
                    onSubmit: { Task { await vm.submit() } },
                    onVoice: { Task { await vm.toggleRecording() } },
                    onCancelRecording: { vm.cancelRecording() },
                    onPhotos: { present(.photo) },
                    onFiles: { present(.files) }
                )

                VStack(alignment: .leading, spacing: LVSpacing.sm) {
                    HStack {
                        Text("Recently saved")
                            .lvFont(.kicker)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Button(action: onOpenDashboard) {
                            HStack(spacing: LVSpacing.xs) {
                                Text("Dashboard")
                                LVIconView(.chevronRight, size: 10, tint: palette.textSecondary)
                            }
                            .lvFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                        }
                    }

                    RecentSavesFeed(
                        pending: vm.visiblePending,
                        files: vm.files.displayedFiles,
                        vaultClient: vaultClient,
                        memoryClient: memoryClient,
                        isLoading: vm.files.isLoading,
                        hasMore: vm.files.nextCursor != nil,
                        onLoadMore: { Task { await vm.files.loadMore() } },
                        onRetry: { row in Task { await vm.retry(row) } },
                        onDiscard: { row in Task { await vm.discard(row) } }
                    )
                }
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.top, LVSpacing.md)
            .padding(.bottom, LVLayout.tabBarClearance)
        }
        .lvBackground()
        .refreshable { await vm.loadFeed() }
        .task { await vm.loadFeed() }
        .task { await vm.loadSpacesIfNeeded() }
        .captureSheet(isPresented: $sheetPresented, initialMode: sheetMode)
    }

    @ViewBuilder
    private func statusBanner(_ toast: CapturePhotosViewModel.ToastKind) -> some View {
        let failed: Bool = if case .failed = toast { true } else { false }
        HStack(spacing: LVSpacing.sm) {
            LVIconView(
                failed ? .exclamationmarkTriangleFill : .checkmarkCircleFill,
                size: 16,
                tint: failed ? palette.accent : palette.glowPrimary
            )
            Text(Self.message(for: toast))
                .lvFont(.footnote)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button("Dismiss") { vm.toast = nil }
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
        // A success clears itself; a failure stays until it is read, because it
        // is the only sign the capture did not happen.
        .task(id: Self.message(for: toast)) {
            guard !failed else { return }
            try? await Task.sleep(for: .seconds(3))
            vm.toast = nil
        }
    }

    private static func message(for toast: CapturePhotosViewModel.ToastKind) -> String {
        switch toast {
        case let .savedOnline(count): return count == 1 ? "Saved." : "Saved \(count) items."
        case .queuedOffline: return "Saved to your vault."
        case let .failed(reason): return reason
        }
    }

    /// Photos and files already work well in the capture sheet — offline
    /// queued, with a Space picker. One tap from the composer is not a worse
    /// product than an inline picker; a second implementation of one is worse
    /// code.
    private func present(_ mode: CaptureSheet.Mode) {
        composerFocused = false
        sheetMode = mode
        sheetPresented = true
    }
}
