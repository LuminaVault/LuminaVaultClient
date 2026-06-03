// LuminaVaultClient/LuminaVaultClient/Features/Insights/InsightDetailView.swift
//
// HER-248 — insight detail. Shows the narrative + its linked source
// memories (fetched per-id; the server has no batch endpoint) with
// dismiss / save-to-vault / share actions. Pushed from both the Insights
// list and the Analytics Patterns section.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class InsightDetailViewModel {
    enum MemoryState: Equatable { case loading, loaded([MemoryDTO]), failed }

    let insight: InsightDTO
    var memories: MemoryState = .loading
    var isDismissed = false
    var isSaving = false
    var statusMessage: String?

    private let memoryClient: any MemoryClientProtocol
    private let insightsClient: any InsightsClientProtocol
    private let uploadClient: any VaultUploadClientProtocol

    init(
        insight: InsightDTO,
        memoryClient: any MemoryClientProtocol,
        insightsClient: any InsightsClientProtocol,
        uploadClient: any VaultUploadClientProtocol,
    ) {
        self.insight = insight
        self.memoryClient = memoryClient
        self.insightsClient = insightsClient
        self.uploadClient = uploadClient
    }

    var shareText: String { "\(insight.headline)\n\n\(insight.summary)" }

    /// Fetches up to 10 linked memories concurrently, tolerating per-id
    /// failures, then restores the original `sourceMemoryIDs` order.
    func loadMemories() async {
        let ids = Array(insight.sourceMemoryIDs.prefix(10))
        guard !ids.isEmpty else { memories = .loaded([]); return }
        let fetched = await withTaskGroup(of: MemoryDTO?.self) { group in
            for id in ids {
                group.addTask { [memoryClient] in try? await memoryClient.get(id: id) }
            }
            var result: [MemoryDTO] = []
            for await memory in group { if let memory { result.append(memory) } }
            return result
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        memories = .loaded(fetched.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) })
    }

    func dismiss() async -> Bool {
        do {
            try await insightsClient.dismiss(id: insight.id)
            isDismissed = true
            return true
        } catch {
            statusMessage = "Couldn't dismiss."
            return false
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let markdown = "# \(insight.headline)\n\n\(insight.summary)\n"
        guard let data = markdown.data(using: .utf8) else { return }
        let slug = insight.headline
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
            .prefix(40)
        do {
            _ = try await uploadClient.uploadNote(
                data: data,
                contentType: "text/markdown",
                relativePath: "insights/\(slug).md",
                spaceID: nil,
                metadata: nil,
            )
            statusMessage = "Saved to vault."
        } catch {
            statusMessage = "Couldn't save."
        }
    }
}

struct InsightDetailView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismissScreen

    @State var vm: InsightDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LVSpacing.lg) {
                header
                actions
                if let message = vm.statusMessage {
                    Text(message)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(palette.textSecondary)
                }
                linkedMemories
            }
            .padding(LVSpacing.lg)
        }
        .navigationTitle("Insight")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .task { await vm.loadMemories() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(vm.insight.section.displayLabel.uppercased())
                .font(LVTypography.microTag.font.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(palette.accent)
            Text(vm.insight.headline)
                .font(LVTypography.bodyEmphasis.font)
                .foregroundStyle(palette.textPrimary)
            Text(vm.insight.summary)
                .font(LVTypography.footnote.font)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var actions: some View {
        HStack(spacing: LVSpacing.md) {
            Button {
                Task { if await vm.dismiss() { dismissScreen() } }
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
            .disabled(vm.isDismissed)

            Button {
                Task { await vm.save() }
            } label: {
                if vm.isSaving {
                    ProgressView()
                } else {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
            }
            .disabled(vm.isSaving)

            ShareLink(item: vm.shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .font(LVTypography.caption.font.weight(.semibold))
        .buttonStyle(.plain)
        .foregroundStyle(palette.primary)
    }

    @ViewBuilder
    private var linkedMemories: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("LINKED MEMORIES")
                .font(LVTypography.microTag.font.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textSecondary)

            switch vm.memories {
            case .loading:
                ProgressView().tint(palette.primary)
            case .failed:
                Text("Couldn't load linked memories.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
            case .loaded(let memories) where memories.isEmpty:
                Text("No linked memories.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
            case .loaded(let memories):
                ForEach(memories) { memory in
                    memoryCard(memory)
                }
            }
        }
    }

    private func memoryCard(_ memory: MemoryDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text(memory.content)
                .font(LVTypography.footnote.font)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(4)
            if let createdAt = memory.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: LVRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.lg)
                .stroke(palette.primary.opacity(0.15), lineWidth: 1),
        )
    }
}

extension InsightDetailView {
    /// HER-248 — build a detail screen from a shared `BaseHTTPClient`.
    /// Both the Insights list and the Analytics Patterns section push via
    /// this so the three read/write clients are wired in one place.
    static func make(insight: InsightDTO, httpClient: BaseHTTPClient) -> InsightDetailView {
        InsightDetailView(vm: InsightDetailViewModel(
            insight: insight,
            memoryClient: MemoryHTTPClient(client: httpClient),
            insightsClient: InsightsHTTPClient(client: httpClient),
            uploadClient: VaultUploadHTTPClient(client: httpClient),
        ))
    }
}

extension InsightSection {
    /// HER-248 — human label shared by the Insights list, Analytics
    /// Patterns section, and the detail header.
    var displayLabel: String {
        switch self {
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .patterns: "Patterns"
        case .contradictions: "Contradictions"
        case .connections: "Connections"
        }
    }
}
