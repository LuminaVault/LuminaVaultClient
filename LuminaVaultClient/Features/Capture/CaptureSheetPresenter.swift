// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureSheetPresenter.swift
//
// One place that knows how to stand up the capture sheet.
//
// Extracted from `CaptureFAB` when the Home composer needed to present the
// same sheet for its photo and file affordances. The composer handles text and
// links itself; photos and files already work well in the sheet — offline
// queued, with a Space picker — so it hands off rather than rebuilding pickers
// that would then drift from the originals.

import SwiftUI

extension View {
    /// Presents the capture sheet in `initialMode`, built from the ambient
    /// `CaptureCoordinator`.
    ///
    /// Callers must also disable their control while the coordinator is cold
    /// (`coordinator?.queue == nil`). The `else` arm here is the seatbelt, not
    /// the fix: a sheet that opens onto "not ready yet" is a worse answer than
    /// a button that is visibly not tappable.
    func captureSheet(
        isPresented: Binding<Bool>,
        initialMode: CaptureSheet.Mode,
        requestedBatchID: UUID? = nil
    ) -> some View {
        modifier(
            CaptureSheetPresenter(
                isPresented: isPresented,
                initialMode: initialMode,
                requestedBatchID: requestedBatchID
            )
        )
    }
}

private struct CaptureSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let initialMode: CaptureSheet.Mode
    let requestedBatchID: UUID?

    @Environment(\.captureCoordinator) private var coordinator

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
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
                    initialMode: initialMode
                )
            } else {
                LVEmptyState(
                    headline: "Capture isn't ready yet",
                    supporting: "Your vault is still being prepared. This will open once it's ready.",
                    primaryCTA: ("Close", { isPresented = false })
                )
            }
        }
    }
}
