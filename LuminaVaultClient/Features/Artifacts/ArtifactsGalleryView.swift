import SwiftUI

@Observable
@MainActor
final class ArtifactsGalleryViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var artifacts: [HermesArtifactDTO] = []
    var filter: HermesArtifactKind?
    private let client: any HermesArtifactsClientProtocol

    init(client: any HermesArtifactsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            artifacts = try await client.list(kind: filter, query: nil).artifacts
            state = .loaded
        } catch {
            state = .failed("Couldn't load artifacts from your Hermes.")
        }
    }

    var images: [HermesArtifactDTO] { artifacts.filter { $0.kind == .image } }
    var filesAndLinks: [HermesArtifactDTO] { artifacts.filter { $0.kind != .image } }
}

struct ArtifactsGalleryView: View {
    @Environment(\.lvPalette) private var palette
    @State var vm: ArtifactsGalleryViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Artifacts")
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All") { vm.filter = nil; Task { await vm.load() } }
                    Button("Images") { vm.filter = .image; Task { await vm.load() } }
                    Button("Files") { vm.filter = .file; Task { await vm.load() } }
                    Button("Links") { vm.filter = .link; Task { await vm.load() } }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case let .failed(message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded where vm.artifacts.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No artifacts yet.",
                supporting: "Images, files and links your Hermes produces in sessions will show up here."
            )
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LVSpacing.md) {
                    if !vm.images.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                            ForEach(vm.images) { artifact in
                                artifactImage(artifact)
                            }
                        }
                    }
                    ForEach(vm.filesAndLinks) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Text(artifact.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.top, LVSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func artifactImage(_ artifact: HermesArtifactDTO) -> some View {
        if let url = URL(string: artifact.href), url.scheme == "http" || url.scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    palette.surface
                }
            }
            .frame(minHeight: 108)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.surface)
                .frame(height: 108)
                .overlay {
                    Text(artifact.label)
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
        }
    }
}
