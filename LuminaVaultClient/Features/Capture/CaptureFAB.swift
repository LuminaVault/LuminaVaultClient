// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureFAB.swift
//
// HER-34 — "+" capture button. Tap opens `CaptureSheet` (HER-256), which
// hosts the photo and text capture flows behind a segmented control. The
// button reads the `CaptureCoordinator` from the environment so it can wire
// the VMs with the live queue + drainer.
//
// HER-255 redesign — two styles. `.floating` is the original 56pt gradient
// disc (no longer mounted by default). `.header` is a compact 38pt disc with
// a glowing ring, sized to sit beside the Hermie avatar inside `LuminaHeader`.

import SwiftUI

struct CaptureFAB: View {
    /// Visual treatment. `.header` matches the 38pt mascot avatar in
    /// `LuminaHeader`; `.floating` is the legacy large overlay disc.
    enum Style {
        case floating
        case header
    }

    @Environment(\.lvPalette) private var palette

    @Environment(\.captureCoordinator) private var coordinator
    @Environment(NotificationRouter.self) private var notificationRouter
    @State private var showingSheet = false
    @State private var requestedBatchID: UUID?

    var style: Style = .floating

    /// Visual shrink applied to the disc *inside* the button label. Hosts used
    /// to wrap the whole `CaptureFAB` in `.scaleEffect`, which shrank the hit
    /// region along with the artwork — the tab-bar FAB bottomed out around
    /// 35pt. Scaling here keeps the tappable frame at its unscaled size.
    var visualScale: CGFloat = 1

    init(style: Style = .floating, visualScale: CGFloat = 1) {
        self.style = style
        self.visualScale = visualScale
    }

    private var diameter: CGFloat {
        style == .header ? 38 : 56
    }

    private var glyphSize: CGFloat {
        style == .header ? 16 : 22
    }

    var body: some View {
        Button {
            requestedBatchID = nil
            showingSheet = true
        } label: {
            label
                // `scaleEffect` leaves layout size untouched, so the label keeps
                // reporting `diameter` and the hit region never drops below it.
                .scaleEffect(visualScale)
                .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("New capture")
        .sheet(isPresented: $showingSheet) {
            if let queue = coordinator?.queue, let ingestionClient = coordinator?.ingestionClient {
                CaptureSheet(
                    photoViewModel: CapturePhotosViewModel(
                        queue: queue,
                        locationService: LocationService(),
                        drainer: coordinator?.drainerHandle ?? .noop,
                        spacesClient: coordinator?.spacesClient
                    ),
                    textViewModel: TextCaptureViewModel(
                        queue: queue,
                        locationService: LocationService(),
                        drainer: coordinator?.drainerHandle ?? .noop,
                        spacesClient: coordinator?.spacesClient
                    ),
                    urlViewModel: URLCaptureViewModel(
                        queue: queue,
                        drainer: coordinator?.drainerHandle ?? .noop,
                        spacesClient: coordinator?.spacesClient
                    ),
                    multimodalViewModel: MultimodalCaptureViewModel(
                        client: ingestionClient,
                        capabilitiesClient: coordinator?.hermesCapabilitiesClient,
                        spacesClient: coordinator?.spacesClient,
                        requestedBatchID: requestedBatchID
                    ),
                    initialMode: requestedBatchID == nil ? .photo : .files
                )
            } else {
                Text("Capture is initializing…")
                    .padding()
            }
        }
        .task(id: notificationRouter.pendingDeepLink) {
            routePendingIngestion()
        }
    }

    private func routePendingIngestion() {
        guard case let .ingestion(batchID, _) = notificationRouter.pendingDeepLink else { return }
        requestedBatchID = batchID
        showingSheet = true
        _ = notificationRouter.consume()
    }

    private var label: some View {
        LVIconView(.plus, size: glyphSize, tint: .white, weight: .semibold)
            .frame(width: diameter, height: diameter)
            .background(
                LinearGradient(
                    colors: [palette.primary, palette.secondary, palette.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .overlay {
                // HER-255 — glowing ring on the compact header style so the
                // "+" reads as a sibling of the Hermie avatar beside it.
                if style == .header {
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
            }
            .shadow(
                color: style == .header ? palette.glowPrimary.opacity(0.7) : .black.opacity(0.25),
                radius: style == .header ? 10 : 8,
                x: 0,
                y: style == .header ? 0 : 4
            )
    }
}

private struct CaptureCoordinatorKey: EnvironmentKey {
    static let defaultValue: CaptureCoordinator? = nil
}

extension EnvironmentValues {
    var captureCoordinator: CaptureCoordinator? {
        get { self[CaptureCoordinatorKey.self] }
        set { self[CaptureCoordinatorKey.self] = newValue }
    }
}
