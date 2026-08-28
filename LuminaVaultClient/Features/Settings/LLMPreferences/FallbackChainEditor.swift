// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/FallbackChainEditor.swift
//
// The reorderable fallback-chain rows for the Intelligence pane. Split out of
// `LLMPreferencesPaneView` when the rows gained stable identity, so the row
// view and its identity contract sit next to each other.

import LuminaVaultShared
import SwiftUI

struct FallbackChainEditor: View {
    @Bindable var viewModel: LLMPreferencesPaneViewModel

    var body: some View {
        // Identity is `FallbackRouteUIModel.id`, not the enumeration offset.
        // Both `.onDelete` and `.onMove` live on this loop, so an
        // offset-keyed identity would let SwiftUI reuse a row — and the
        // uncommitted text in its `TextField` — across a reorder, committing
        // the edit onto whichever route landed at that index.
        ForEach(viewModel.fallbackChain) { step in
            FallbackChainRow(
                step: step,
                onSelectProvider: { viewModel.updateFallback(id: step.id, provider: $0) },
                onEditModel: { viewModel.updateFallback(id: step.id, model: $0) }
            )
        }
        .onDelete { offsets in
            viewModel.removeFallback(at: offsets)
        }
        .onMove { from, to in
            viewModel.moveFallback(from: from, to: to)
        }
    }
}

/// A single `(provider, model)` step. Both callbacks close over `step.id`, so
/// even a view SwiftUI chose to reuse writes back to the route it is showing.
private struct FallbackChainRow: View {
    let step: FallbackRouteUIModel
    let onSelectProvider: (ProviderID) -> Void
    let onEditModel: (String) -> Void

    var body: some View {
        HStack {
            // Labelled for VoiceOver, hidden visually — the row reads as
            // "provider · model" and a visible label would repeat the header.
            Picker("Provider", selection: Binding(
                get: { step.provider },
                set: onSelectProvider
            )) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Text(ProvidersPaneViewModel.displayName(for: provider)).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 160)

            TextField("Model", text: Binding(
                get: { step.model },
                set: onEditModel
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel("Fallback model")
        }
    }
}
