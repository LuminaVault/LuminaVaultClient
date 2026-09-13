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
                HomeComposer(
                    text: $vm.text,
                    focused: $composerFocused,
                    isSaving: vm.saving,
                    detectedLink: vm.detectedLink,
                    canSave: vm.canSave,
                    isRecording: vm.isRecording,
                    onSubmit: { Task { await vm.submit() } },
                    onVoice: { Task { await vm.toggleRecording() } },
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
                        pending: vm.pending,
                        files: vm.files.displayedFiles,
                        vaultClient: vaultClient,
                        memoryClient: memoryClient,
                        isLoading: vm.files.isLoading,
                        hasMore: vm.files.nextCursor != nil,
                        onLoadMore: { Task { await vm.files.loadMore() } }
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
        .captureSheet(isPresented: $sheetPresented, initialMode: sheetMode)
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
