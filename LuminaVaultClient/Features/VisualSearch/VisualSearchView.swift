// LuminaVaultClient/LuminaVaultClient/Features/VisualSearch/VisualSearchView.swift
//
// HER-157 — PhotosPicker entry to the visual-search pipeline. v1 surface.
// HER-104 (tab bar shell) wires this into MainTabView once it lands.

import PhotosUI
import SwiftUI

struct VisualSearchView: View {
    @State private var viewModel: VisualSearchViewModel
    @State private var pickedItem: PhotosPickerItem?

    init(viewModel: VisualSearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    pickerSection
                    switch viewModel.state {
                    case .idle:
                        EmptyView()
                    case .extractingText:
                        Section { ProgressView("Reading text…").frame(maxWidth: .infinity) }
                    case .querying:
                        Section { ProgressView("Asking Hermes…").frame(maxWidth: .infinity) }
                    case let .results(response, extractedText):
                        VisualSearchResultsSection(response: response, extractedText: extractedText)
                    case let .error(message):
                        errorSection(message: message)
                    }
                }
                .scrollContentBackground(.hidden)
                if case .idle = viewModel.state {
                    LVEmptyState(
                        mascot: .thinking,
                        headline: "Drop an image to search.",
                        supporting: "Long-press a photo with text and Hermes will hunt your memories.",
                        backgroundImage: "Lumina/Backgrounds/neural-network"
                    )
                    .allowsHitTesting(false)
                    .padding(.bottom, 80)
                }
            }
            .lvBackground()
            .navigationTitle("Visual search")
            .navigationBarTitleDisplayMode(.inline)
            .lvNavBrand(position: .topLeading)
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.runSearch(imageData: data)
                }
            }
        }
    }

    private var pickerSection: some View {
        Section {
            PhotosPicker(
                selection: $pickedItem,
                matching: .images,
                photoLibrary: .shared(),
            ) {
                Label("Pick an image", systemImage: "photo.on.rectangle.angled")
            }
        } footer: {
            Text("Long-press a photo of dense text — a book cover, a menu, a sign — and Hermes will search your memories for related notes.")
        }
    }

    @ViewBuilder
    private func errorSection(message: String) -> some View {
        Section {
            Text(message).foregroundStyle(.red)
            if !viewModel.lastExtractedText.isEmpty {
                Button("Retry") { Task { await viewModel.retryQuery() } }
            }
            Button("Pick another image") { viewModel.reset() }
        }
    }
}

#Preview {
    VisualSearchView(viewModel: VisualSearchViewModel(
        ocr: PreviewOCRService(),
        client: PreviewMemoryQueryClient(),
        telemetry: NoopTelemetry(),
    ))
}

// MARK: - Preview-only fakes (kept here so the #Preview block compiles
// without leaking into the test target).

private struct PreviewOCRService: ImageOCRServiceProtocol {
    func extractText(from _: Data, locale _: String?) async throws -> String {
        "Hermes, by Lewis Hyde"
    }
}

private struct PreviewMemoryQueryClient: MemoryQueryClientProtocol {
    func query(text _: String, limit _: Int?) async throws -> QueryResponse {
        QueryResponse(
            summary: "You captured a passage about Hermes the trickster last May.",
            hits: [
                QueryHitDTO(
                    id: UUID(),
                    content: "Hermes — the trickster who breaks rules to make new ones.",
                    distance: 0.21,
                    createdAt: Date(),
                ),
            ],
        )
    }
}
