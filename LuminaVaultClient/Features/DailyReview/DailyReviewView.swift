// LuminaVaultClient/LuminaVaultClient/Features/DailyReview/DailyReviewView.swift
//
// HER-154 scaffold — daily review surface:
//   - empty-state hero with mascot (.idle)
//   - streak counter pill
//   - "Hermes' reflection of the day" card
//   - this-week memos list with per-row ShareLink
//   - suggested actions row
//   - pull-to-refresh wired to VM
//
// Sections render only when the corresponding fields are populated;
// the view degrades gracefully when the server omits any of them
// (digest is the source of truth).
import SwiftUI

struct DailyReviewView: View {
    @State var vm: DailyReviewViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
            .refreshable { await vm.refresh() }
            .background(Color(.systemBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.loadIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .empty, .loading:
            EmptyHero(mascotState: vm.mascotState)
        case .loaded(let digest):
            LoadedSections(digest: digest)
        case .failed(let message):
            ErrorRow(message: message)
        }
    }
}

// MARK: - Empty / loading

private struct EmptyHero: View {
    let mascotState: HermieMascotState
    var body: some View {
        VStack(spacing: 16) {
            HermieMascotView(state: mascotState, size: 140, fallbackImageName: "OnboardingMascot")
            Text("Lumina's getting today ready.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Your reflection, this week's memos, and your streak will show up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

private struct ErrorRow: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Loaded sections

private struct LoadedSections: View {
    let digest: DailyReviewDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let streak = digest.streakDays, streak > 0 {
                StreakPill(days: streak)
            }
            if let reflection = digest.reflection, !reflection.isEmpty {
                ReflectionCard(text: reflection)
            }
            if !digest.memories.isEmpty {
                MemoryList(memories: digest.memories)
            }
            if !digest.suggestedActions.isEmpty {
                SuggestedActions(actions: digest.suggestedActions)
            }
        }
    }
}

private struct StreakPill: View {
    let days: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("\(days)-day streak")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.capsule)
    }
}

private struct ReflectionCard: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hermes' reflection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.leading)
            HStack {
                Spacer(minLength: 0)
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Share reflection")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct MemoryList: View {
    let memories: [QueryHitDTO]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(memories) { memory in
                    MemoryRow(memory: memory)
                    if memory.id != memories.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}

private struct MemoryRow: View {
    let memory: QueryHitDTO
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.content)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let createdAt = memory.createdAt {
                    Text(createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            ShareLink(item: memory.content) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Share memo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SuggestedActions: View {
    let actions: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        Text(action)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(.capsule)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    let digest = DailyReviewDigest(
        date: Date(),
        memories: [
            QueryHitDTO(id: UUID(), content: "Read Hyperion. Finally understand the Shrike.", distance: 0.1, createdAt: Date()),
            QueryHitDTO(id: UUID(), content: "Vault structure feels right when memo precedes capture.", distance: 0.2, createdAt: Date().addingTimeInterval(-86_400)),
        ],
        achievements: [],
        soulExcerpt: "",
        suggestedActions: ["Go deeper on Hyperion", "Capture a thought", "Open last week"],
        streakDays: 7,
        reflection: "You noticed a pattern this week — vault structure follows your thinking, not the other way around. That's the kind of observation worth keeping.",
    )
    return DailyReviewView(vm: DailyReviewViewModel(client: PreviewClient(digest: digest)))
}

#Preview("Empty") {
    DailyReviewView(vm: DailyReviewViewModel(client: PreviewClient(digest: nil)))
}

private struct PreviewClient: DailyReviewClientProtocol {
    let digest: DailyReviewDigest?
    func fetchToday() async throws -> DailyReviewDigest {
        if let digest { return digest }
        try await Task.sleep(for: .seconds(1))
        return DailyReviewDigest(date: Date())
    }
}
#endif
