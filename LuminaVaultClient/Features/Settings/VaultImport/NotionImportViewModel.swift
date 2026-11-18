// LuminaVaultClient/LuminaVaultClient/Features/Settings/VaultImport/NotionImportViewModel.swift
//
// Backlog E7.4: import a Notion export ZIP (spec 2026-11-18, D7/D8). Two
// steps against `POST /v1/vault/import/notion`: a dry run that writes nothing
// and returns the report, then the same request for real.
//
// The picked file is copied into the app's temp folder while its security
// scope is held, so the two uploads that follow need no scope and a file that
// lives in iCloud Drive cannot go away between them.

import Foundation
import Observation

@MainActor
@Observable
final class NotionImportViewModel {
    enum Phase: Equatable {
        /// No file yet.
        case idle
        /// Copying the picked file.
        case reading
        /// A file is ready; nothing checked.
        case picked
        /// The dry run is in flight.
        case checking
        /// `report` holds the dry run.
        case checked
        /// The import is in flight.
        case importing
        /// `report` holds what was imported.
        case done
    }

    /// The server answers 413 above 200 MB. Read as MiB so a file near the
    /// line is the server's call, not ours.
    nonisolated static let defaultMaxBytes: Int64 = 200 * 1024 * 1024
    nonisolated static let defaultSpaceName = "Notion"

    private(set) var phase: Phase = .idle
    private(set) var report: VaultNotionImportReport?
    private(set) var errorMessage: String?
    private(set) var fileName: String?
    private(set) var fileBytes: Int64 = 0
    /// The fraction of the ZIP sent, while a request is in flight. At 1 the
    /// server has the file and the wait is for its answer.
    private(set) var uploadProgress: Double?

    /// True once the upload is done and the server is working.
    var isWaitingForServer: Bool {
        (uploadProgress ?? 0) >= 1
    }

    /// The Space the export lands in. Editing it makes a finished dry run
    /// stale: the report described a different destination.
    var spaceName = NotionImportViewModel.defaultSpaceName {
        didSet {
            guard spaceName != oldValue, phase == .checked else { return }
            report = nil
            phase = .picked
        }
    }

    private let client: VaultImportClientProtocol
    private let maxBytes: Int64
    /// Our own copy of the picked ZIP; deleted when this lets go of it.
    private var staged: StagedFile?

    init(client: VaultImportClientProtocol, maxBytes: Int64 = NotionImportViewModel.defaultMaxBytes) {
        self.client = client
        self.maxBytes = maxBytes
    }

    var isBusy: Bool {
        phase == .reading || phase == .checking || phase == .importing
    }

    var trimmedSpaceName: String {
        spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCheck: Bool {
        (phase == .picked || phase == .checked) && !trimmedSpaceName.isEmpty
    }

    var canImport: Bool {
        phase == .checked && !trimmedSpaceName.isEmpty
    }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file)
    }

    /// Take the file the user picked. A file over the limit is refused here,
    /// before a byte is read or sent.
    func pick(_ url: URL) async {
        discardCopy()
        report = nil
        errorMessage = nil
        fileName = nil
        fileBytes = 0
        phase = .reading
        let limit = maxBytes
        let outcome = await Task.detached { Self.stage(url, maxBytes: limit) }.value
        switch outcome {
        case let .success(picked):
            staged = picked.file
            fileName = picked.name
            fileBytes = picked.bytes
            phase = .picked
        case let .failure(failure):
            errorMessage = failure.message
            phase = .idle
        }
    }

    func pickFailed(_ error: any Error) {
        guard !error.isBenignCancellation else { return }
        errorMessage = error.localizedDescription
    }

    /// The dry run: what the import would do, with nothing written.
    func check() async {
        guard canCheck else { return }
        await send(dryRun: true, working: .checking, success: .checked, fallback: .picked)
    }

    /// The real import. Only offered after a dry run of the same file and
    /// Space name.
    func runImport() async {
        guard canImport else { return }
        await send(dryRun: false, working: .importing, success: .done, fallback: .checked)
    }

    /// Back to the start, for another export.
    func reset() {
        discardCopy()
        report = nil
        errorMessage = nil
        fileName = nil
        fileBytes = 0
        phase = .idle
    }

    private func send(dryRun: Bool, working: Phase, success: Phase, fallback: Phase) async {
        guard let staged else { return }
        errorMessage = nil
        phase = working
        uploadProgress = 0
        defer { uploadProgress = nil }
        do {
            // Streamed from disk by the client: a 200 MB export never sits in
            // memory.
            report = try await client.importNotion(
                zipFile: staged.url,
                space: trimmedSpaceName,
                dryRun: dryRun,
                onConflict: "skip",
                onUploadProgress: { [weak self] fraction in
                    Task { @MainActor in self?.noteUpload(fraction) }
                }
            )
            phase = success
            if !dryRun {
                discardCopy()
            }
        } catch {
            phase = fallback
            // The screen went away mid-request; that is not a failure to show.
            if !error.isBenignCancellation {
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Progress arrives on the session's delegate queue, hopped here. Only
    /// forward, and only while a request is in flight: a late report must not
    /// resurrect the bar after the answer came.
    private func noteUpload(_ fraction: Double) {
        guard let current = uploadProgress, fraction > current else { return }
        uploadProgress = min(1, fraction)
    }

    private func discardCopy() {
        staged = nil
    }

    /// The server's own `{"error":{"message"}}` text when it sent one (a 400
    /// names the limit that was broken). Otherwise a sentence for the statuses
    /// the route documents; a proxy can answer 413 before the app does.
    nonisolated static func message(for error: any Error) -> String {
        guard case let APIError.httpError(status, data) = error else {
            return error.localizedDescription
        }
        if let structured = StructuredAPIError.parse(from: data) {
            return structured.message
        }
        switch status {
        case 400: return "That file isn't a Notion export the server can read."
        case 413: return tooBigMessage
        case 507: return "The server is out of storage space. Try again later."
        default: return "Server error (\(status))."
        }
    }

    nonisolated static let tooBigMessage =
        "That export is over 200 MB. Export fewer pages from Notion, or split it, and try again."

    // MARK: - Staging the picked file

    /// The temp copy of the export, in a folder of its own. Removing the
    /// folder in `deinit` covers every way out: a finished import, another
    /// pick, a reset, and the screen (and its view model) going away.
    final nonisolated class StagedFile: Sendable {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        deinit {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    nonisolated struct Staged: Sendable {
        let file: StagedFile
        let name: String
        let bytes: Int64
    }

    nonisolated struct StageFailure: Error, Sendable {
        let message: String
    }

    /// Checks the size and copies the file into a folder of its own under the
    /// temp directory. Synchronous file work; call it off the main actor.
    nonisolated static func stage(_ url: URL, maxBytes: Int64) -> Result<Staged, StageFailure> {
        // False for a URL that needs no scope (a test's temp file); fine.
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return .failure(StageFailure(message: "Couldn't read that file."))
        }
        let bytes = Int64(size)
        guard bytes > 0 else {
            return .failure(StageFailure(message: "That file is empty."))
        }
        guard bytes <= maxBytes else {
            return .failure(StageFailure(message: tooBigMessage))
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notion-import-\(UUID().uuidString)", isDirectory: true)
        let copy = folder.appendingPathComponent("export.zip")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return .failure(StageFailure(message: "Couldn't read that file: \(error.localizedDescription)"))
        }
        return .success(Staged(file: StagedFile(url: copy), name: url.lastPathComponent, bytes: bytes))
    }
}
