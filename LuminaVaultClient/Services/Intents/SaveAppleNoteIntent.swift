// LuminaVaultClient/LuminaVaultClient/Services/Intents/SaveAppleNoteIntent.swift
//
// Apple Notes → LuminaVault, through Shortcuts.
//
// iOS gives apps no API to read Notes, but Shortcuts can: "Find Notes" then
// "Repeat with Each" then this intent turns every note into a vault note.
// A shared Shortcut does that in one tap, and a Shortcuts automation can
// re-run it on a schedule.
//
// Re-running must not duplicate anything:
//   * Each note gets a stable capture id derived from its title and creation
//     date, so its vault file name is the same every run and the server
//     overwrites it (and updates its linked memory) instead of adding one.
//   * A note whose content has not changed since the last run is skipped
//     entirely, so a nightly run over hundreds of notes sends only the edits.

import AppIntents
import CryptoKit
import Foundation

struct SaveAppleNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Note to LuminaVault"
    static var description = IntentDescription(
        "Copy a note from the Notes app into your vault. Run it again after editing the note and the vault copy is updated, not duplicated.",
        categoryName: "Capture"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var noteTitle: String

    @Parameter(title: "Body")
    var body: String

    @Parameter(title: "Creation Date")
    var created: Date?

    @Parameter(title: "Modification Date")
    var modified: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$noteTitle) to LuminaVault") {
            \.$body
            \.$created
            \.$modified
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let note = AppleNoteImport(title: noteTitle, body: body, created: created, modified: modified)
        guard !note.isEmpty else {
            return .result(dialog: "That note is empty.")
        }
        let ledger = AppleNoteImportLedger()
        guard ledger.needsUpload(note) else {
            return .result(dialog: "“\(note.displayTitle)” is already up to date.")
        }

        // Same offline-first queue as every capture: it drains when online.
        let container = try CaptureQueue.makeProductionContainer()
        let queue = CaptureQueue(container: container)
        try await queue.enqueue(CaptureSnapshot.text(id: note.captureID, body: note.markdown, createdAt: note.created ?? .now))
        ledger.recordUpload(note)

        return .result(dialog: "Saved “\(note.displayTitle)” to your vault.")
    }
}

/// One Apple Note as it will land in the vault. Pure, so the identity and
/// dedupe rules are testable without Shortcuts.
struct AppleNoteImport: Equatable {
    let title: String
    let body: String
    let created: Date?
    let modified: Date?

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled note" : trimmed
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Who this note is, independent of its content: title plus creation
    /// time (to the second). Editing the body keeps the identity; a second
    /// note with the same title does not collide unless it was created in
    /// the same second.
    var identity: String {
        let stamp = created.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "apple-note|\(displayTitle)|\(stamp)"
    }

    /// A UUID fixed by `identity`: version-5-shaped bits over a SHA-256.
    var captureID: UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// What the vault note contains.
    var markdown: String {
        var lines = ["# \(displayTitle)", ""]
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Shortcuts often passes the title again as the body's first line.
        let withoutRepeatedTitle = text.hasPrefix(displayTitle)
            ? String(text.dropFirst(displayTitle.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : text
        if !withoutRepeatedTitle.isEmpty {
            lines.append(withoutRepeatedTitle)
            lines.append("")
        }
        let formatter = ISO8601DateFormatter()
        var provenance = "_From Apple Notes"
        if let created { provenance += ", created \(formatter.string(from: created))" }
        if let modified { provenance += ", edited \(formatter.string(from: modified))" }
        lines.append(provenance + "._")
        return lines.joined(separator: "\n")
    }

    /// Changes whenever what the vault would store changes.
    var contentHash: String {
        SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Remembers what each note looked like when it was last queued, so an
/// unchanged note is not sent again.
struct AppleNoteImportLedger {
    static let key = "lv.appleNotes.importedHashes"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func needsUpload(_ note: AppleNoteImport) -> Bool {
        hashes()[note.captureID.uuidString] != note.contentHash
    }

    func recordUpload(_ note: AppleNoteImport) {
        var all = hashes()
        all[note.captureID.uuidString] = note.contentHash
        defaults.set(all, forKey: Self.key)
    }

    private func hashes() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
