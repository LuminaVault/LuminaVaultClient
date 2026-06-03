// LuminaVaultClient/LuminaVaultClient/Features/Insights/InsightsListView.swift
//
// HER-248 — Insights screen. Consumes /v1/insights (HER-244 stub).
// Empty until pattern/contradiction skills land insight generation.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class InsightsListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var insights: [InsightDTO] = []
    var section: InsightSection?
    private let client: InsightsClientProtocol

    init(client: InsightsClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            let response = try await client.list(section: section, limit: 50)
            insights = response.insights.sorted { $0.createdAt > $1.createdAt }
            state = .loaded
        } catch {
            state = .failed("Couldn't load insights.")
        }
    }

    func setSection(_ section: InsightSection?) async {
        self.section = section
        await load()
    }
}

struct InsightsListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: InsightsListViewModel
    /// HER-248 — when wired, cards push the insight detail screen. Optional
    /// so older call sites / previews keep compiling.
    var httpClient: BaseHTTPClient? = nil

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            VStack(spacing: LVSpacing.md) {
                filter
                content
            }
            .padding(.top, LVSpacing.md)
        }
        .navigationTitle("Insights")
        .lvBackground()
        .task { await vm.load() }
    }

    private var filter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LVSpacing.sm) {
                chip("All", isSelected: vm.section == nil) {
                    Task { await vm.setSection(nil) }
                }
                ForEach(InsightSection.allCases, id: \.self) { section in
                    chip(label(for: section), isSelected: vm.section == section) {
                        Task { await vm.setSection(section) }
                    }
                }
            }
            .padding(.horizontal, LVSpacing.lg)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
                .frame(maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .font(LVTypography.footnote.font)
                .foregroundStyle(Color.lvTextMuted)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded where vm.insights.isEmpty:
            VStack(spacing: LVSpacing.sm) {
                Text("Lumina is still listening.")
                    .font(LVTypography.fieldLabel.font)
                    .foregroundStyle(palette.textPrimary)
                Text("Insights will land here when she spots patterns.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, LVSpacing.xxl)
            .frame(maxHeight: .infinity, alignment: .top)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: LVSpacing.md) {
                    ForEach(vm.insights) { insight in
                        row(insight)
                    }
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.bottom, LVSpacing.lg)
            }
        }
    }

    @ViewBuilder
    private func row(_ insight: InsightDTO) -> some View {
        if let httpClient {
            NavigationLink {
                InsightDetailView.make(insight: insight, httpClient: httpClient)
            } label: {
                card(insight)
            }
            .buttonStyle(.plain)
        } else {
            card(insight)
        }
    }

    private func card(_ insight: InsightDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(label(for: insight.section).uppercased())
                .font(LVTypography.microTag.font.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(palette.accent)
            Text(insight.headline)
                .font(LVTypography.bodyEmphasis.font)
                .foregroundStyle(palette.textPrimary)
            Text(insight.summary)
                .font(LVTypography.footnote.font)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: LVRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.lg)
                .stroke(palette.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LVTypography.caption.font.weight(.semibold))
                .padding(.horizontal, LVSpacing.md)
                .padding(.vertical, LVSpacing.sm)
                .background(isSelected ? palette.primary : palette.backgroundBase.opacity(0.6))
                .foregroundStyle(isSelected ? palette.backgroundBase : palette.textSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func label(for section: InsightSection) -> String {
        switch section {
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .patterns: "Patterns"
        case .contradictions: "Contradictions"
        case .connections: "Connections"
        }
    }
}
