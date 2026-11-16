// LuminaVaultClient/LuminaVaultClient/Features/Vault/Templates/NoteShortcutsViewModel.swift
// Backlog E6.4: "Today's note" and "New from template". The server owns both:
// it creates the daily note once per day across devices, and renders the
// template variables, so iOS and web make the same note.
import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class NoteShortcutsViewModel {
    static let templatesSpace = "templates"

    private(set) var templates: [VaultFileDTO] = []
    private(set) var loadingTemplates = false
    private(set) var working = false
    var selectedTemplate: String?
    var title = ""
    var error: String?
    /// The note to open in the reader; set by either shortcut.
    var openedNote: VaultFileDTO?

    private let client: VaultClientProtocol
    private let timeZone: @Sendable () -> String

    init(client: VaultClientProtocol, timeZone: @escaping @Sendable () -> String = { TimeZone.current.identifier }) {
        self.client = client
        self.timeZone = timeZone
    }

    var canCreate: Bool {
        !working && selectedTemplate != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openToday() async {
        working = true
        defer { working = false }
        do {
            openedNote = try await client.dailyNote(tz: timeZone())
        } catch {
            self.error = Self.message(error, fallback: "Could not open today's note.")
        }
    }

    /// The user's templates. A user who never used them has none, so the
    /// starter set is written once and the list read again.
    func loadTemplates() async {
        loadingTemplates = true
        error = nil
        defer { loadingTemplates = false }
        do {
            var found = try await listTemplates()
            if found.isEmpty {
                _ = try await client.seedTemplates()
                found = try await listTemplates()
            }
            templates = found
            if selectedTemplate == nil || !found.contains(where: { $0.path == selectedTemplate }) {
                selectedTemplate = found.first?.path
            }
        } catch {
            self.error = Self.message(error, fallback: "Could not load your templates.")
        }
    }

    /// Returns true when the note was created, so the sheet can close.
    @discardableResult
    func create() async -> Bool {
        guard canCreate, let selectedTemplate else { return false }
        working = true
        defer { working = false }
        do {
            openedNote = try await client.noteFromTemplate(VaultFromTemplateRequest(
                template: Self.fileName(selectedTemplate),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                tz: timeZone()
            ))
            title = ""
            return true
        } catch {
            self.error = Self.message(error, fallback: "Could not create the note.")
            return false
        }
    }

    private func listTemplates() async throws -> [VaultFileDTO] {
        let response = try await client.listFiles(
            spaceSlug: Self.templatesSpace, q: nil, before: nil, after: nil, limit: 100
        )
        return response.files
            .filter { $0.path.hasSuffix(".md") || $0.path.hasSuffix(".markdown") }
            .sorted { Self.label($0.path).localizedCompare(Self.label($1.path)) == .orderedAscending }
    }

    /// `templates/meeting.md` → `meeting.md`, the name the server expects.
    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// `templates/weekly-review.md` → `Weekly review`.
    static func label(_ path: String) -> String {
        var base = fileName(path)
        for ext in [".markdown", ".md"] where base.hasSuffix(ext) {
            base = String(base.dropLast(ext.count))
            break
        }
        let words = base.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return base }
        return first.uppercased() + words.dropFirst()
    }

    static func message(_ error: Error, fallback: String) -> String {
        if case let APIError.httpError(statusCode, _) = error, statusCode == 409 {
            return "A note with that name already exists. Pick another title."
        }
        return (error as? APIError)?.errorDescription ?? fallback
    }
}
