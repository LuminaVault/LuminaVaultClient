// LuminaVaultClient/LuminaVaultClient/Features/Brief/BriefView.swift
//
// The daily brief, as a sheet: the day, a short list of cards in the
// server's order — each with its why line and 👍 / 👎 / dismiss — and then an
// end. Opened from Home's "Your brief" row, from `luminavault://brief` (the
// brief's chat message and its push), and from the push's "Open" action.
//
// What a card points at opens from it: a memory in `MemoryDetailSheet`, the
// Open loops card's commitments right on the card with Done / Drop, and
// every open loop behind its "See all".

import LuminaVaultShared
import SwiftUI

struct BriefView: View {
    @State private var vm: BriefViewModel
    /// The memory a card's ref opened.
    @State private var openMemory: BriefMemoryLink?
    @State private var showingCommitments = false
    /// Bumped by "Try again". Zero is the first load.
    @State private var reloadToken = 0
    /// Bumped when the full list closes: it can close or reopen any loop.
    @State private var commitmentsReloadToken = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private let memoryClient: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?
    /// "Due today" is relative; snapshot suites pin it.
    private let now: () -> Date

    init(
        viewModel: BriefViewModel,
        memoryClient: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        _vm = State(initialValue: viewModel)
        self.memoryClient = memoryClient
        self.spacesClient = spacesClient
        self.now = now
    }

    var body: some View {
        NavigationStack {
            content
                .background(palette.backgroundBase)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task(id: reloadToken) { await vm.load() }
                .task(id: commitmentsReloadToken) {
                    guard commitmentsReloadToken > 0 else { return }
                    await vm.loadCommitments()
                }
                .navigationDestination(isPresented: $showingCommitments) {
                    CommitmentsListView(
                        viewModel: CommitmentsListViewModel(client: vm.commitmentsClient),
                        now: now
                    )
                }
                .onChange(of: showingCommitments) { _, showing in
                    if !showing { commitmentsReloadToken += 1 }
                }
                .sheet(item: $openMemory) { link in
                    MemoryDetailSheet(memoryID: link.id, client: memoryClient, spacesClient: spacesClient)
                }
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading your brief")
        case let .failed(message):
            ContentUnavailableView {
                Label(message, systemImage: "sun.horizon")
            } actions: {
                Button("Try again") { reloadToken += 1 }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: LVSpacing.xs, bottom: LVSpacing.xs, trailing: LVSpacing.xs))
                    .listRowBackground(Color.clear)
            }

            if vm.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(vm.cards) { card in
                Section {
                    BriefCardView(
                        card: card,
                        vm: vm,
                        now: now,
                        onOpenMemory: { openMemory = BriefMemoryLink(id: $0) },
                        onSeeAllLoops: { showingCommitments = true }
                    )
                }
            }

            if let brief = vm.brief {
                Section {
                    endNote(brief.endNote)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
        // Reduced motion drops the slide (see `lvAnimation`).
        .lvAnimation(LVMotion.standard, value: vm.cards.map(\.id))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text("Your brief")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(vm.dateText)
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: LVSpacing.md) {
            Image(systemName: "sun.horizon")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("No brief yet today.")
                .lvFont(.headline)
                .foregroundStyle(palette.textPrimary)
            Text("It arrives each morning — I'll let you know when it's ready.")
                .lvFont(.callout)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    /// The brief has an end, and says so.
    private func endNote(_ text: String) -> some View {
        VStack(spacing: LVSpacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(text.isEmpty ? BriefViewModel.defaultEndNote : text)
                .lvFont(.callout)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.base)
    }
}

// MARK: - Card

/// One card: its title and why, its body (or, for Open loops, the loops with
/// Done / Drop), what it points at, and 👍 / 👎 / dismiss.
private struct BriefCardView: View {
    let card: BriefCardDTO
    let vm: BriefViewModel
    let now: () -> Date
    let onOpenMemory: (UUID) -> Void
    let onSeeAllLoops: () -> Void

    @Environment(\.lvPalette) private var palette

    private var isPending: Bool {
        vm.pendingCardIDs.contains(card.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            heading
            cardBody
            footer
            if let message = vm.errorMessage(forCard: card.id) {
                BriefErrorLabel(message: message)
            }
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
            Image(systemName: Self.symbol(for: card.kind))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .lvFont(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let why = card.why, !why.isEmpty {
                    Text(why)
                        .lvFont(.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityLabel("Why: \(why)")
                }
            }
            Spacer(minLength: LVSpacing.sm)
            Button {
                Task { await vm.dismiss(card) }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: LVSize.tapTarget, height: LVSize.tapTarget, alignment: .topTrailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(isPending)
            .accessibilityLabel("Dismiss this card")
            .padding(.top, -LVSpacing.sm)
        }
    }

    @ViewBuilder private var cardBody: some View {
        if vm.hasCommitments(card), let loops = vm.commitments(for: card) {
            if loops.isEmpty {
                Text("All closed. Nice.")
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: LVSpacing.md) {
                    ForEach(loops) { loop in
                        BriefLoopRow(
                            commitment: loop,
                            now: now(),
                            isPending: vm.pendingCommitmentIDs.contains(loop.id),
                            errorMessage: vm.errorMessage(forCommitment: loop.id),
                            onDone: { Task { await vm.markDone(loop) } },
                            onDrop: { Task { await vm.drop(loop) } }
                        )
                    }
                }
            }
        } else if !card.body.isEmpty {
            Text(Self.attributed(card.body))
                .lvFont(.callout)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: LVSpacing.sm) {
            refs
            Spacer(minLength: 0)
            reactionButton(.up, symbol: "hand.thumbsup", label: "Helpful")
            reactionButton(.down, symbol: "hand.thumbsdown", label: "Not helpful")
        }
    }

    /// What the card points at that this app can open: its memories and,
    /// for commitments, the full list. Events and SOUL changes have nowhere
    /// to go yet.
    @ViewBuilder private var refs: some View {
        let memories = vm.memoryIDs(for: card)
        if memories.count == 1, let id = memories.first {
            Button("Open memory", systemImage: "doc.text") { onOpenMemory(id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if memories.count > 1 {
            Menu {
                ForEach(Array(memories.enumerated()), id: \.element) { index, id in
                    Button("Memory \(index + 1)") { onOpenMemory(id) }
                }
            } label: {
                Label("Memories (\(memories.count))", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if vm.hasCommitments(card) {
            Button("See all", action: onSeeAllLoops)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("See all open loops")
        }
    }

    private func reactionButton(_ action: BriefCardFeedbackAction, symbol: String, label: String) -> some View {
        let chosen = vm.reactions[card.id] == action
        return Button {
            Task { await vm.react(action, to: card) }
        } label: {
            Image(systemName: chosen ? "\(symbol).fill" : symbol)
                .foregroundStyle(chosen ? palette.accent : palette.textSecondary)
                .frame(width: LVSize.tapTarget, height: LVSize.tapTarget / 1.5)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(isPending)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    static func symbol(for kind: BriefCardKind) -> String {
        switch kind {
        case .today: "calendar"
        case .openLoops: "circle.dashed"
        case .toRevisit: "arrow.counterclockwise"
        case .learned: "brain.head.profile"
        case .onYourMind: "sparkles"
        case .weather: "cloud.sun"
        case .inbox: "tray"
        case .other, .unknown: "text.alignleft"
        }
    }

    /// Light markdown — bold, italics, links — with line breaks kept and
    /// `- ` list lines drawn as bullets.
    static func attributed(_ body: String) -> AttributedString {
        let bulleted = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return "• " + trimmed.dropFirst(2)
                }
                return String(line)
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(bulleted)
    }
}

/// One open loop on the brief's card, with Done and Drop.
private struct BriefLoopRow: View {
    let commitment: CommitmentDTO
    let now: Date
    let isPending: Bool
    let errorMessage: String?
    let onDone: () -> Void
    let onDrop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            CommitmentRow(commitment: commitment, detail: detail, errorMessage: errorMessage)
            HStack(spacing: LVSpacing.sm) {
                Button("Done", systemImage: "checkmark", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Mark done: \(commitment.text)")
                Button("Drop", action: onDrop)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Drop: \(commitment.text)")
            }
            .disabled(isPending)
        }
    }

    private var detail: CommitmentRow.Detail? {
        guard let dueAt = commitment.dueAt else { return nil }
        let due = CommitmentCopy.dueText(dueAt, now: now)
        return CommitmentRow.Detail(text: due.text, isWarning: due.isOverdue)
    }
}

private struct BriefErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .lvFont(.footnote)
            .foregroundStyle(.orange)
    }
}

/// `.sheet(item:)` fodder for a memory a card opened.
private struct BriefMemoryLink: Identifiable, Equatable {
    let id: UUID
}
