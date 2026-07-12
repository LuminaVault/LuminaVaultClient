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

                Picker("Save to Space", selection: $viewModel.selectedSpaceID) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(viewModel.spaces) { space in
                        Text(space.name).tag(Optional(space.id))
                    }
                }

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
                if viewModel.captureBlocked {
                    Text("Your connected Hermes does not advertise multimodal ingestion with remote source access. Upgrade or enable its ingestion API before uploading files.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Multimodal capture unavailable for connected Hermes")
                }
                if let batch = viewModel.latestBatch {
                    VStack(alignment: .leading, spacing: LVSpacing.sm) {
                        HStack {
                            Label("Saved to vault · \(batch.completed) of \(batch.total) processed", systemImage: "checkmark.circle")
                            Spacer()
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await viewModel.refreshStatus() }
                            }
                            .labelStyle(.iconOnly)
                        }
                        ForEach(batch.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.fileName ?? item.url ?? "Capture").lineLimit(1)
                                Text(item.state.rawValue.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let summary = item.summary {
                                    Text(summary).font(.footnote)
                                }
                                if let credibility = item.credibility {
                                    Text("Source credibility: \(credibility.score.map(String.init) ?? "N/A")")
                                        .font(.caption.bold())
                                    Text(credibility.rationale).font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = item.error {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                }
                                HStack {
                                    if item.state == .failed || item.state == .blockedCapability {
                                        Button("Retry", systemImage: "arrow.clockwise") {
                                            Task { await viewModel.retry(itemID: item.id) }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if item.state != .completed && item.state != .cancelled {
                                        Button("Cancel", role: .destructive) {
                                            Task { await viewModel.cancel(itemID: item.id) }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding()
                            .background(.thinMaterial, in: .rect(cornerRadius: LVRadius.card))
                        }
                    }
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
        .task(id: viewModel.latestBatch?.id) {
            await viewModel.loadSpaces()
            await viewModel.loadCapabilities()
            await viewModel.monitorStatus()
        }
    }
}
