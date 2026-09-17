// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureToolbarItem.swift
//
// The one "+" a tab is allowed. Home has none — its composer is the entry —
// so every other tab gets this instead, in the place iOS puts a create
// action: the trailing end of the navigation bar.
//
// A `ToolbarContent` cannot own the `@State` the sheet needs, so this ships
// as a modifier that adds both the item and the presentation together. That
// also keeps the two from drifting apart at a call site.

import SwiftUI

extension View {
    /// Adds a trailing "+" to the navigation bar that opens the capture sheet.
    func captureToolbarItem() -> some View {
        modifier(CaptureToolbarItemModifier())
    }
}

private struct CaptureToolbarItemModifier: ViewModifier {
    @Environment(\.captureCoordinator) private var coordinator
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Capture", systemImage: "plus") { presented = true }
                        // The coordinator is nil until the vault is prepared,
                        // and a sheet that opens onto "not ready yet" is a
                        // worse answer than a button that is visibly not
                        // tappable.
                        .disabled(coordinator?.queue == nil || coordinator?.ingestionClient == nil)
                }
            }
            .captureSheet(isPresented: $presented, initialMode: .photo)
    }
}
