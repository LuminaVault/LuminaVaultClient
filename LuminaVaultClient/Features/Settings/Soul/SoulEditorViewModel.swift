// LuminaVaultClient/LuminaVaultClient/Features/Settings/Soul/SoulEditorViewModel.swift
//
// Phase 1 — post-onboarding SOUL.md (agent personality) editor. Drives
// GET/PUT/DELETE /v1/soul via SoulClientProtocol. Onboarding writes the
// first SOUL.md; this lets the user revise it later, apply a personality
// preset, or reset to the bootstrap template.

import Foundation
import LuminaVaultShared

/// Client-side personality presets. Hermes exposes `/personality` presets in
/// the TUI; we ship equivalents as local templates the user can drop into the
/// editor and then review + save. These are starting points, not server state.
enum SoulPreset: String, CaseIterable, Identifiable {
    case concise = "Concise"
    case warm = "Warm"
    case analyst = "Analyst"
    case mentor = "Mentor"

    var id: String { rawValue }

    var template: String {
        switch self {
        case .concise:
            return """
            # Personality

            You are direct and efficient. Lead with the answer, then the
            reasoning only if it adds value. Avoid filler, hedging, and
            restating the question. Prefer short paragraphs and lists.
            """
        case .warm:
            return """
            # Personality

            You are warm, encouraging, and patient. Acknowledge the person's
            intent before diving in. Celebrate progress, soften corrections,
            and keep an approachable, human tone without being saccharine.
            """
        case .analyst:
            return """
            # Personality

            You are a rigorous analyst. Separate facts from assumptions, surface
            trade-offs explicitly, and quantify when you can. Flag uncertainty
            and what would change your conclusion. Avoid unfounded confidence.
            """
        case .mentor:
            return """
            # Personality

            You are a senior mentor. Explain the "why" behind advice, point to
            the principle as well as the fix, and ask a sharpening question when
            the goal is ambiguous. Push for the durable solution over the quick
            patch.
            """
        }
    }
}

@MainActor
@Observable
final class SoulEditorViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// Mirrors the server's 64 KiB SOUL.md cap (`SOULService.maxSizeBytes`).
    /// The cap applies to the FULL document (locked core included), so the
    /// user's editable budget is `maxBytes − (prefix + core)`.
    static let maxBytes = 64 * 1024

    private let client: any SoulClientProtocol

    var state: LoadState = .loading
    /// Live editor buffer — the EDITABLE portion only (template v2 splits
    /// the document around the server-managed locked core covenant).
    var markdown: String = ""
    /// Locked front-matter + core covenant from the last load; nil core for
    /// pre-v2 documents the server hasn't migrated yet.
    private(set) var parts: SoulDocumentParts?
    /// Last editable value loaded from / saved to the server — basis for
    /// dirty/revert.
    private(set) var loadedMarkdown: String = ""
    private(set) var updatedAt: Date?
    var isSaving = false
    var actionError: String?

    init(client: any SoulClientProtocol) {
        self.client = client
    }

    /// The read-only core covenant to render above the editor, if any.
    var lockedCore: String? { parts?.core }

    var isDirty: Bool { markdown != loadedMarkdown }
    /// Byte size of the assembled document — what the server actually caps.
    var byteCount: Int { assembled().lengthOfBytes(using: .utf8) }
    var isOverLimit: Bool { byteCount > Self.maxBytes }
    var canSave: Bool { isDirty && !isOverLimit && !isSaving }

    private func assembled() -> String {
        guard let parts else { return markdown }
        return SoulCoreParser.assemble(parts, editable: markdown)
    }

    func load() async {
        state = .loading
        do {
            try await refresh()
            state = .ready
        } catch {
            state = .failed("Couldn't load your agent's personality.")
        }
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            let response = try await client.put(SoulPutRequest(markdown: assembled()))
            apply(response)
        } catch {
            actionError = "Couldn't save — \(error.localizedDescription)"
        }
    }

    /// Discards unsaved edits, restoring the last loaded value.
    func revert() {
        markdown = loadedMarkdown
        actionError = nil
    }

    /// Resets SOUL.md to the shipped bootstrap template (server 204), then
    /// re-fetches so the editor shows the regenerated content.
    func resetToDefault() async {
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            try await client.delete()
            try await refresh()
        } catch {
            actionError = "Couldn't reset — \(error.localizedDescription)"
        }
    }

    /// Fills the editor with a preset template. Replaces only the editable
    /// portion — the locked core stays. The user still reviews and saves —
    /// this never writes on its own.
    func applyPreset(_ preset: SoulPreset) {
        markdown = preset.template
        actionError = nil
    }

    // MARK: - Internals

    private func refresh() async throws {
        let response = try await client.get()
        apply(response)
    }

    private func apply(_ response: SoulResponse) {
        let split = SoulCoreParser.parse(response.markdown)
        parts = split
        loadedMarkdown = split.editable
        markdown = split.editable
        updatedAt = response.updatedAt
    }
}
