// LuminaVaultClient/LuminaVaultClient/Features/Commitments/CommitmentsListView.swift
//
// "Open loops" — every commitment kb-compile found in the user's notes, open
// by default, with Done and Dropped one segment away. Pushed from the brief's
// Open loops card ("See all").
//
// Done / Drop on an open loop, Reopen on a closed one: as swipe actions, in
// the row's context menu, and — through the swipe actions — to VoiceOver.

import LuminaVaultShared
import SwiftUI

struct CommitmentsListView: View {
    @State private var vm: CommitmentsListViewModel
    /// What the segmented control shows; the view model follows it.
    @State private var segment: CommitmentsListViewModel.Segment
    /// Bumped by "Try again".
    @State private var reloadToken = 0

    @Environment(\.lvPalette) private var palette

    /// "Due today" is relative; snapshot suites pin it.
    private let now: () -> Date

    init(viewModel: CommitmentsListViewModel, now: @escaping () -> Date = Date.init) {
        _vm = State(initialValue: viewModel)
        _segment = State(initialValue: viewModel.segment)
        self.now = now
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $segment) {
                    ForEach(CommitmentsListViewModel.Segment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: LVSpacing.xs, trailing: 0))
                .listRowBackground(Color.clear)
            }

            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.backgroundBase)
        .navigationTitle("Open loops")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task(id: SegmentLoad(segment: segment, token: reloadToken)) { await vm.select(segment) }
        // Reduced motion drops the slide (see `lvAnimation`).
        .lvAnimation(LVMotion.standard, value: vm.items.map(\.id))
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .loading:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LVSpacing.xl)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Loading open loops")
            }
        case let .failed(message):
            Section {
                ContentUnavailableView {
                    Label(message, systemImage: "circle.dashed")
                } actions: {
                    Button("Try again") { reloadToken += 1 }
                }
                .listRowBackground(Color.clear)
            }
        case .loaded:
            if vm.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(vm.items) { commitment in
                        row(for: commitment)
                    }
                } footer: {
                    if vm.segment == .open {
                        Text("Swipe right when it's done, left to let it go.")
                    }
                }
            }
        }
    }

    private func row(for commitment: CommitmentDTO) -> some View {
        CommitmentRow(
            commitment: commitment,
            detail: detail(for: commitment),
            errorMessage: vm.errorMessage(for: commitment.id)
        )
        .disabled(vm.pendingIDs.contains(commitment.id))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if vm.segment == .open {
                Button("Done", systemImage: "checkmark") { Task { await vm.markDone(commitment) } }
                    .tint(.green)
            } else {
                Button("Reopen", systemImage: "arrow.uturn.backward") { Task { await vm.reopen(commitment) } }
                    .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if vm.segment == .open {
                Button("Drop", systemImage: "xmark") { Task { await vm.drop(commitment) } }
                    .tint(.orange)
            }
        }
        .contextMenu {
            if vm.segment == .open {
                Button("Done", systemImage: "checkmark") { Task { await vm.markDone(commitment) } }
                Button("Drop", systemImage: "xmark") { Task { await vm.drop(commitment) } }
            } else {
                Button("Reopen", systemImage: "arrow.uturn.backward") { Task { await vm.reopen(commitment) } }
            }
        }
    }

    /// The due line on an open loop; when it was closed on the others.
    private func detail(for commitment: CommitmentDTO) -> CommitmentRow.Detail? {
        switch vm.segment {
        case .open:
            guard let dueAt = commitment.dueAt else { return nil }
            let due = CommitmentCopy.dueText(dueAt, now: now())
            return CommitmentRow.Detail(text: due.text, isWarning: due.isOverdue)
        case .done, .dropped:
            guard let doneAt = commitment.doneAt else { return nil }
            let verb = vm.segment == .done ? "Done" : "Dropped"
            return CommitmentRow.Detail(
                text: "\(verb) \(doneAt.formatted(.dateTime.month(.abbreviated).day()))",
                isWarning: false
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: LVSpacing.md) {
            Image(systemName: emptySymbol)
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(emptyText)
                .lvFont(.callout)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.xl)
    }

    private var emptySymbol: String {
        switch vm.segment {
        case .open: "checkmark.circle"
        case .done: "circle.dashed"
        case .dropped: "tray"
        }
    }

    private var emptyText: String {
        switch vm.segment {
        case .open: "No open loops. When a note says \u{201C}I'll…\u{201D} or \u{201C}I need to…\u{201D}, it lands here."
        case .done: "Nothing marked done yet."
        case .dropped: "Nothing dropped."
        }
    }
}

/// `.task(id:)` key: a new segment, or "Try again" on the same one.
private struct SegmentLoad: Equatable {
    let segment: CommitmentsListViewModel.Segment
    let token: Int
}

/// One commitment: what was promised, when it is due (or when it was
/// closed), and an inline error when an answer did not land. Shared with the
/// brief's Open loops card.
struct CommitmentRow: View {
    struct Detail: Equatable {
        let text: String
        let isWarning: Bool
    }

    let commitment: CommitmentDTO
    let detail: Detail?
    let errorMessage: String?

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commitment.text)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                if let detail {
                    Text(detail.text)
                        .lvFont(.caption)
                        .foregroundStyle(detail.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(palette.textSecondary))
                }
            }
            .accessibilityElement(children: .combine)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .lvFont(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
