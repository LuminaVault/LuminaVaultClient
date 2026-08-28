// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultFilesViewModel.swift
// HER-105: drives `VaultFilesListView` — paginated list of files inside a
// single Space. Holds the local list, pagination cursor, loading state.
// Delete/move are optimistic; failures roll back and surface an error
// banner (same pattern as `SpacesViewModel`).
import Foundation
import SwiftUI

@Observable
@MainActor
final class VaultFilesViewModel {
    private let vaultClient: VaultClientProtocol
    private let spaceSlug: String

    /// Segmented filter for the list. UI-only, but it lives here because
    /// `displayedFiles` derives from it and must be recomputed on change,
    /// not on every body pass.
    enum NoteFilter: String, CaseIterable {
        case all = "All"
        case notes = "Notes"
        case todos = "Todos"
    }

    var files: [VaultFileDTO] = [] {
        didSet { rebuildDisplayedFiles() }
    }

    var filter: NoteFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            rebuildDisplayedFiles()
        }
    }

    /// `files` after the filter and, for Todos, the due-date sort. Maintained
    /// on mutation. It used to be a computed property on the view consumed
    /// directly by `ForEach`, so the whole paginated list was re-filtered and
    /// re-sorted on every body pass — including every scroll frame.
    private(set) var displayedFiles: [VaultFileDTO] = []

    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var nextCursor: Date?

    init(vaultClient: VaultClientProtocol, spaceSlug: String) {
        self.vaultClient = vaultClient
        self.spaceSlug = spaceSlug
    }

    /// Applies the segmented filter and, for the Todos view, sorts open items
    /// by soonest due (undated last) and sinks completed ones to the bottom.
    private func rebuildDisplayedFiles() {
        switch filter {
        case .all:
            displayedFiles = files
        case .notes:
            displayedFiles = files.filter { $0.metadata?.isTodo != true }
        case .todos:
            displayedFiles = files
                .filter { $0.metadata?.isTodo == true }
                .sorted { lhs, rhs in
                    let lhsDone = lhs.metadata?.done == true
                    let rhsDone = rhs.metadata?.done == true
                    if lhsDone != rhsDone { return !lhsDone } // open before done
                    let lhsDue = lhs.metadata?.dueAt ?? .distantFuture
                    let rhsDue = rhs.metadata?.dueAt ?? .distantFuture
                    return lhsDue < rhsDue
                }
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let resp = try await vaultClient.listFiles(
                spaceSlug: spaceSlug, q: nil, before: nil, after: nil, limit: 50,
            )
            files = resp.files
            nextCursor = resp.nextBefore
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let resp = try await vaultClient.listFiles(
                spaceSlug: spaceSlug, q: nil, before: cursor, after: nil, limit: 50,
            )
            files.append(contentsOf: resp.files)
            nextCursor = resp.nextBefore
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Optimistic delete; rolls back on failure.
    func delete(file: VaultFileDTO) async {
        let index = files.firstIndex(where: { $0.id == file.id })
        if let index { files.remove(at: index) }
        do {
            try await vaultClient.deleteFile(relativePath: file.path)
        } catch {
            if let index { files.insert(file, at: index) }
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Optimistic move. `newPath` is server-relative (e.g. `notes/foo.md`).
    func move(file: VaultFileDTO, newPath: String) async {
        let index = files.firstIndex(where: { $0.id == file.id })
        guard let index else { return }
        let original = files[index]
        do {
            let updated = try await vaultClient.moveFile(from: file.path, to: newPath)
            files[index] = updated
        } catch {
            files[index] = original
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
