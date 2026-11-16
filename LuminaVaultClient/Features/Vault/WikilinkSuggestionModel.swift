// LuminaVaultClient/LuminaVaultClient/Features/Vault/WikilinkSuggestionModel.swift
// Backlog E5.3: drives the `[[` suggestion row under the note editor. The view
// calls `update(text:cursor:)` on every edit; this debounces, fetches notes
// (`GET /v1/vault/files?q=`) or a note's headings, and publishes suggestions.
import Foundation

@Observable
@MainActor
final class WikilinkSuggestionModel {
    struct Suggestion: Identifiable, Equatable {
        let label: String
        let detail: String
        /// The link target written between `[[` and `]]`.
        let target: String
        var id: String {
            target
        }
    }

    private let vaultClient: VaultClientProtocol
    private let debounce: Duration

    private(set) var suggestions: [Suggestion] = []
    private var pending: Task<Void, Never>?
    /// Note path → its headings, for the life of one edit.
    private var headingCache: [String: [String]] = [:]

    init(vaultClient: VaultClientProtocol, debounce: Duration = .milliseconds(150)) {
        self.vaultClient = vaultClient
        self.debounce = debounce
    }

    /// Recomputes for the text and cursor. Outside `[[…` it clears at once.
    func update(text: String, cursor: String.Index?) {
        pending?.cancel()
        guard let cursor, let ctx = WikilinkCompletion.context(in: text, cursor: cursor) else {
            suggestions = []
            return
        }
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let found = await self.load(ctx)
            guard !Task.isCancelled else { return }
            self.suggestions = found
        }
    }

    /// Waits for the current fetch; for tests.
    func settle() async {
        await pending?.value
    }

    func dismiss() {
        pending?.cancel()
        suggestions = []
    }

    /// Writes the link. Returns the new text and the cursor offset after `]]`,
    /// or nil when the cursor is no longer inside a `[[…`.
    func accept(_ suggestion: Suggestion, text: String, cursor: String.Index) -> (String, Int)? {
        guard let ctx = WikilinkCompletion.context(in: text, cursor: cursor) else { return nil }
        dismiss()
        return WikilinkCompletion.apply(target: suggestion.target, to: text, context: ctx, cursor: cursor)
    }

    private func load(_ ctx: WikilinkCompletion.Context) async -> [Suggestion] {
        do {
            if let note = ctx.note {
                return try await headingSuggestions(note: note, prefix: ctx.heading ?? "")
            }
            let paths = try await searchPaths(ctx.query)
            return WikilinkCompletion.rankNotes(paths, query: ctx.query).map {
                Suggestion(label: $0.label, detail: $0.detail, target: $0.label)
            }
        } catch {
            return []
        }
    }

    private func searchPaths(_ query: String) async throws -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return try await vaultClient.listFiles(
            spaceSlug: nil, q: q.isEmpty ? nil : q, before: nil, after: nil, limit: 50
        ).files.map(\.path)
    }

    private func headingSuggestions(note: String, prefix: String) async throws -> [Suggestion] {
        let name = note.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        let tail = name.split(separator: "/").last.map(String.init) ?? name
        let matches = try await WikilinkCompletion.rankNotes(searchPaths(tail), query: tail, limit: 50)
            .filter { $0.label.lowercased() == name.lowercased() }
        guard matches.count == 1, let path = matches.first?.path else { return [] }
        let headings: [String]
        if let cached = headingCache[path] {
            headings = cached
        } else {
            let (data, _) = try await vaultClient.readFile(relativePath: path)
            headings = WikilinkCompletion.headings(of: String(decoding: data, as: UTF8.self))
            headingCache[path] = headings
        }
        return WikilinkCompletion.rankHeadings(headings, prefix: prefix).map {
            Suggestion(label: $0, detail: "", target: "\(note)#\($0)")
        }
    }
}
