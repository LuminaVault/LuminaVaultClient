import SwiftUI
import UniformTypeIdentifiers

struct MultimodalCaptureView: View {
    @Bindable var viewModel: MultimodalCaptureViewModel
    @State private var showingImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LVSpacing.base) {
                Button("Choose files", systemImage: "doc.badge.plus") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Choose PDFs, images, audio, or video for Hermes to process")

                ForEach(viewModel.selectedFiles, id: \.self) { url in
                    HStack {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button("Remove", systemImage: "xmark.circle") { viewModel.remove(url) }
                            .labelStyle(.iconOnly)
                    }
                }

                TextField("Paste a web page URL", text: $viewModel.urlText, axis: .vertical)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.thinMaterial, in: .rect(cornerRadius: LVRadius.card))

                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote).accessibilityLabel("Capture failed: \(error)")
                }
                if let batch = viewModel.latestBatch {
                    Label("Saved to vault · \(batch.completed) of \(batch.total) processed", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LVSpacing.base)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .image, .audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                viewModel.add(urls)
            }
        }
    }
}
