// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureFAB.swift
//
// HER-34 — floating "+" button rendered on top of MainTabView. Tap
// opens `CaptureSheet` (HER-256), which hosts both the photo and text
// capture flows behind a segmented control. The button reads the
// `CaptureCoordinator` from the environment so it can wire the VMs
// with the live queue + drainer.

import SwiftUI

struct CaptureFAB: View {
    @Environment(\.captureCoordinator) private var coordinator
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [.lvCyan, .lvBlue, .lvAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    ),
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("New capture")
        .sheet(isPresented: $showingSheet) {
            if let queue = coordinator?.queue {
                CaptureSheet(
                    photoViewModel: CapturePhotosViewModel(
                        queue: queue,
                        locationService: LocationService(),
                        drainer: coordinator?.drainerHandle ?? .noop,
                        spacesClient: coordinator?.spacesClient,
                    ),
                    textViewModel: TextCaptureViewModel(
                        queue: queue,
                        locationService: LocationService(),
                        drainer: coordinator?.drainerHandle ?? .noop,
                    ),
                    urlViewModel: URLCaptureViewModel(
                        queue: queue,
                        drainer: coordinator?.drainerHandle ?? .noop,
                        spacesClient: coordinator?.spacesClient,
                    ),
                )
            } else {
                Text("Capture is initializing…")
                    .padding()
            }
        }
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
