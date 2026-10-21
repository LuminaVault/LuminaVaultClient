// LuminaVaultClient/LuminaVaultClient/Features/Vault/WikilinkMarkdownView.swift
// Markdown reader body with tappable Obsidian wikilinks.

import Algorithms
import MarkdownUI
import SwiftUI

struct WikilinkMarkdownView: View {
    @Environment(\.lvPalette) private var palette
    /// Routes the app's own links (`luminavault://brief`, `…/memory/<id>`,
    /// `…/meeting/<id>`) in place. Optional: a preview or a reader outside
    /// the signed-in shell has none, and those links then go to the system
    /// as before.
    @Environment(NotificationRouter.self) private var notificationRouter: NotificationRouter?

    let markdown: String
    let renderedMarkdownOverride: String?
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol

    @State private var noteToOpen: VaultFileDTO?
    @State private var noteCandidates: [VaultFileDTO] = []
    @State private var memoryToShow: MemoryDTO?
    @State private var linkError: String?
    @State private var isResolvingLink = false

    private var renderedMarkdown: String {
        renderedMarkdownOverride ?? WikilinkParser.markdownByRenderingLinks(in: markdown)
    }

    init(
        markdown: String,
        renderedMarkdown: String? = nil,
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryClientProtocol
    ) {
        self.markdown = markdown
        self.renderedMarkdownOverride = renderedMarkdown
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            markdownText
            if isResolvingLink {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .background(navigationLink)
        .environment(\.openURL, OpenURLAction { url in
            if let link = WikilinkParser.link(from: url) {
                Task { await open(link) }
                return .handled
            }
            // An app link in a message — the daily brief's "[Your brief is
            // ready — 4 cards](luminavault://brief)" above all — opens here,
            // through the same router a push tap uses, instead of a round
            // trip through the system that lands on `onOpenURL` anyway.
            if let router = notificationRouter,
               let appLink = Self.inAppLink(for: url)
            {
                Task { @MainActor in router.pendingDeepLink = appLink }
                return .handled
            }
            return .systemAction
        })
        .confirmationDialog(
            "Choose note",
            isPresented: Binding(
                get: { !noteCandidates.isEmpty },
                set: { if !$0 { noteCandidates = [] } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(noteCandidates) { file in
                Button(file.path) {
                    noteToOpen = file
                    noteCandidates = []
                }
            }
            Button("Cancel", role: .cancel) {
                noteCandidates = []
            }
        }
        .sheet(item: $memoryToShow) { memory in
            MemoryWikilinkSheet(memory: memory)
        }
        .alert(
            "Link unavailable",
            isPresented: Binding(
                get: { linkError != nil },
                set: { if !$0 { linkError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
    }

    /// The deep link an app URL in a message stands for, or nil for
    /// anything the router does not know (web links, other schemes).
    static func inAppLink(for url: URL) -> APNSDeepLink? {
        let link = NotificationRouter.deepLink(from: url)
        return link == .none ? nil : link
    }

    // Full GitHub-flavored block rendering via MarkdownUI. Wikilinks are
    // pre-rewritten into standard markdown links by `renderedMarkdown`, and
    // taps route through the `\.openURL` action installed on `body`'s VStack —
    // so `[[note]]` / `[[memory:uuid]]` navigation is preserved.
    private var markdownText: some View {
        Markdown(renderedMarkdown)
            .markdownTheme(.luminaVault(palette))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var navigationLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { noteToOpen != nil },
                set: { if !$0 { noteToOpen = nil } }
            )
        ) {
            if let noteToOpen {
                MarkdownReaderView(
                    file: noteToOpen,
                    vaultClient: vaultClient,
                    memoryClient: memoryClient
                )
            }
        } label: {
            EmptyView()
        }
        .hidden()
    }

    @MainActor
    private func open(_ link: Wikilink) async {
        switch link.kind {
        case let .note(target):
            await openNote(target)
        case let .memory(id):
            await openMemory(id)
        }
    }

    @MainActor
    private func openNote(_ target: String) async {
        isResolvingLink = true
        defer { isResolvingLink = false }
        do {
            let response = try await vaultClient.listFiles(
                spaceSlug: nil,
                q: target,
                before: nil,
                after: nil,
                limit: 20
            )
            let candidates = noteMatches(for: target, in: response.files)
            if candidates.count == 1 {
                noteToOpen = candidates[0]
            } else if candidates.count > 1 {
                noteCandidates = candidates
            } else {
                linkError = "No note matched [[\(target)]]."
            }
        } catch {
            linkError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func openMemory(_ id: UUID) async {
        isResolvingLink = true
        defer { isResolvingLink = false }
        do {
            memoryToShow = try await memoryClient.get(id: id)
        } catch {
            linkError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func noteMatches(for target: String, in files: [VaultFileDTO]) -> [VaultFileDTO] {
        WikilinkResolver.noteMatches(for: target, in: files)
    }
}

/// HER-155 follow-up — pure note-resolution helpers extracted off
/// `WikilinkMarkdownView` so they can be unit-tested without spinning
/// up a SwiftUI view hierarchy.
enum WikilinkResolver {
    static func noteMatches(for target: String, in files: [VaultFileDTO]) -> [VaultFileDTO] {
        let markdownFiles = files.filter { file in
            file.contentType.contains("markdown") || file.path.lowercased().hasSuffix(".md")
        }
        let exact = markdownFiles.filter { file in
            normalizedNoteKey(file.path) == normalizedNoteKey(target)
                || normalizedNoteKey((file.path as NSString).lastPathComponent) == normalizedNoteKey(target)
        }
        if !exact.isEmpty { return exact }
        return markdownFiles
    }

    static func normalizedNoteKey(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".md") { value.removeLast(3) }
        return value
    }
}

/// Read-only view of one memory: a `[[memory:…]]` link in an answer, or a
/// source chip under it.
struct MemoryWikilinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let memory: MemoryDTO

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(memory.content)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)

                    if !memory.tags.isEmpty {
                        tagList
                    }

                    if let createdAt = memory.createdAt {
                        Text(createdAt, style: .date)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lvBackground()
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var tagList: some View {
        FlowLayout(spacing: 8) {
            // De-duplicated: `id: \.self` needs unique elements, and a memory
            // can carry the same tag twice.
            ForEach(Array(memory.tags.uniqued()), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.lvGlass))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(
            width: width,
            height: rows.reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if current.width + size.width + (current.items.isEmpty ? 0 : spacing) > width, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.append(index: index, size: size, spacing: spacing)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty { width += spacing }
            items.append((index, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
