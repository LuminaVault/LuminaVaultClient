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
    @State var vm: InsightsListViewModel

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            VStack(spacing: 12) {
                filter
                content
            }
            .padding(.top, 12)
        }
        .navigationTitle("Insights")
        .lvBackground()
        .task { await vm.load() }
    }

    private var filter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: vm.section == nil) {
                    Task { await vm.setSection(nil) }
                }
                ForEach(InsightSection.allCases, id: \.self) { section in
                    chip(label(for: section), isSelected: vm.section == section) {
                        Task { await vm.setSection(section) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(.lvCyan)
                .frame(maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded where vm.insights.isEmpty:
            VStack(spacing: 8) {
                Text("Lumina is still listening.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.lvTextPrimary)
                Text("Insights will land here when she spots patterns.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lvTextSub)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 40)
            .frame(maxHeight: .infinity, alignment: .top)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.insights) { insight in
                        card(insight)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func card(_ insight: InsightDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label(for: insight.section).uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.lvAmber)
            Text(insight.headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.lvTextPrimary)
            Text(insight.summary)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextSub)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lvNavy.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.lvCyan.opacity(0.15), lineWidth: 1)
        )
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.lvCyan : Color.lvNavy.opacity(0.6))
                .foregroundStyle(isSelected ? Color.lvNavy : Color.lvTextSub)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func label(for section: InsightSection) -> String {
        switch section {
        case .thisWeek: "This week"
        case .patterns: "Patterns"
        case .contradictions: "Contradictions"
        case .connections: "Connections"
        }
    }
}
