// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeNewsTickerStrip.swift
//
// One headline at a time, rotating, under the glance strip. Reduce Motion
// turns the rotation into a short static list. Tapping opens the publisher
// in an in-app Safari sheet; nothing is republished here.

import LuminaVaultShared
import SafariServices
import SwiftUI

struct HomeNewsTickerStrip: View {
    @Bindable var viewModel: NewsTickerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var index = 0
    @State private var opened: URL?

    private let rotation: Duration = .seconds(6)
    private let refreshInterval: TimeInterval = 300

    var body: some View {
        Group {
            if !viewModel.isHidden {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if case .loading = viewModel.state {
                        row(placeholder)
                            .redacted(reason: .placeholder)
                    } else if reduceMotion {
                        ForEach(viewModel.items.prefix(3)) { item in
                            row(item)
                        }
                    } else if let item = current {
                        row(item)
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: index)
                .task(id: viewModel.items.count) {
                    guard !reduceMotion, viewModel.items.count > 1 else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: rotation)
                        guard !viewModel.items.isEmpty else { return }
                        index = (index + 1) % viewModel.items.count
                    }
                }
            }
        }
        .task {
            viewModel.loadFromCache()
            await viewModel.refreshIfStale(maxAge: refreshInterval)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))
                await viewModel.refreshIfStale(maxAge: refreshInterval)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshIfStale(maxAge: refreshInterval) }
        }
        .sheet(item: $opened) { url in
            SafariView(url: url).ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Breaking news")
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.isStale {
                Text("· updated earlier")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var current: NewsTickerItemDTO? {
        guard !viewModel.items.isEmpty else { return nil }
        return viewModel.items[index % viewModel.items.count]
    }

    private var placeholder: NewsTickerItemDTO {
        NewsTickerItemDTO(id: "placeholder", title: "Loading the latest headlines", url: nil, source: "Source", sourceUrl: nil, publishedAt: .now)
    }

    @ViewBuilder
    private func row(_ item: NewsTickerItemDTO) -> some View {
        Button {
            if let raw = item.url, let url = URL(string: raw) { opened = url }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(item.source) · \(item.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the publisher")
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// In-app Safari, so a headline never leaves the app's back-stack.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}
