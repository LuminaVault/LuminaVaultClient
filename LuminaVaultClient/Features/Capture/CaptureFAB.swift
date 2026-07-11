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
    @State private var showingSheet = false

    var style: Style = .floating

    init(style: Style = .floating) {
        self.style = style
    }

    private var diameter: CGFloat {
        style == .header ? 38 : 56
    }

    private var glyphSize: CGFloat {
        style == .header ? 16 : 22
    }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            label
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
                        capabilitiesClient: coordinator?.hermesCapabilitiesClient
                    )
                )
            } else {
                Text("Capture is initializing…")
                    .padding()
            }
        }
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
