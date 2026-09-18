// LuminaVaultClient/LuminaVaultClient/Features/Workspace/WorkspaceViewModel.swift
//
// State for the workspace screen: a file tree, the changed-file list, and a
// diff or a file on the detail side.
//
// Reads only. The server exposes nothing that writes, so nothing here could
// stage, commit or push even by accident.
//
// Kept deliberately in step with the web `WorkspaceViewModel`: same states,
// same ordering rules, same treatment of "no checkout". The two render the
// same endpoints, so a difference between them is a bug on one platform
// rather than a platform difference.

import Foundation
import LuminaVaultShared
import os

private let log = Logger(subsystem: "com.luminavault", category: "workspace")

/// The code the server sends when a tenant has no remote Hermes.
///
/// `hermes_mirror_unsupported`, not anything workspace-specific: the surface
/// reuses the mirror transport's errors. Verified against staging — an earlier
/// version of the web client guessed a workspace-specific code, which nothing
/// emits, and every tenant without a checkout saw a red error instead of the
/// explanation.
private let unsupportedCode = "hermes_mirror_unsupported"

@Observable
@MainActor
final class WorkspaceViewModel {
    enum Selection: Equatable {
        case none
        case file(path: String)
        case diff(path: String)
    }

    private(set) var root = ""
    /// Directory currently shown in the tree.
    private(set) var cwd = ""
    private(set) var entries: [HermesWorkspaceFileEntryDTO] = []
    private(set) var status: HermesWorkspaceStatusDTO?

    private(set) var selection: Selection = .none
    private(set) var fileContent: String?
    private(set) var diffText: String?
    private(set) var diffTruncated = false

    private(set) var isLoadingTree = false
    private(set) var isLoadingDetail = false
    private(set) var error: String?
    /// This tenant has no remote Hermes to inspect. A different state from an
    /// error: nothing is broken, there is simply no checkout.
    private(set) var isUnsupported = false

    private let client: any HermesWorkspaceClientProtocol
    private var treeTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    init(client: any HermesWorkspaceClientProtocol) {
        self.client = client
    }

    var changes: [HermesWorkspaceChangeDTO] { status?.changes ?? [] }

    var canGoUp: Bool {
        cwd != root && Self.parentPath(cwd) != nil
    }

    /// Total lines added and removed across the change set, for a summary.
    var churn: (added: Int, removed: Int) {
        changes.reduce(into: (added: 0, removed: 0)) { total, change in
            total.added += change.added
            total.removed += change.removed
        }
    }

    func open(root: String) async {
        self.root = root
        selection = .none
        fileContent = nil
        diffText = nil
        isUnsupported = false
        error = nil
        async let status: Void = loadStatus()
        async let tree: Void = list(path: root)
        _ = await (status, tree)
    }

    func list(path: String) async {
        treeTask?.cancel()
        isLoadingTree = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let listing = try await client.listing(path: path)
                guard !Task.isCancelled else { return }
                cwd = path
                entries = Self.sorted(listing.entries)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                apply(error: error)
            }
            isLoadingTree = false
        }
        treeTask = task
        await task.value
    }

    func goUp() async {
        guard let parent = Self.parentPath(cwd) else { return }
        await list(path: parent)
    }

    func open(entry: HermesWorkspaceFileEntryDTO) async {
        if entry.isDirectory {
            await list(path: entry.path)
        } else {
            await showFile(path: entry.path)
        }
    }

    func showFile(path: String) async {
        selection = .file(path: path)
        await loadDetail {
            let file = try await self.client.file(path: path)
            self.fileContent = file.content
            self.diffText = nil
        }
    }

    func showDiff(file: String) async {
        selection = .diff(path: file)
        await loadDetail {
            let diff = try await self.client.diff(repoPath: self.root, file: file)
            self.diffText = diff.diff
            self.diffTruncated = diff.truncated
            self.fileContent = nil
        }
    }

    func loadStatus() async {
        do {
            status = try await client.status(path: root)
        } catch {
            apply(error: error)
        }
    }

    // MARK: - Helpers

    private func loadDetail(_ body: @escaping () async throws -> Void) async {
        detailTask?.cancel()
        isLoadingDetail = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await body()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                apply(error: error)
            }
            isLoadingDetail = false
        }
        detailTask = task
        await task.value
    }

    private func apply(error: any Error) {
        // Read the server's own envelope rather than pattern-matching the
        // error's description. `String(describing:)` on `httpError` prints the
        // byte count, not the body, so a substring check there silently never
        // matches — which is exactly how this was written the first time.
        let structured: StructuredAPIError? = if case let .httpError(_, data) = error as? APIError {
            StructuredAPIError.parse(from: data)
        } else {
            nil
        }

        if structured?.code == unsupportedCode || structured?.message.contains(unsupportedCode) == true {
            isUnsupported = true
            self.error = nil
            return
        }

        log.warning("workspace read failed: \(String(describing: error), privacy: .public)")
        self.error = structured?.message
            ?? (error as? LocalizedError)?.errorDescription
            ?? "Could not read the workspace."
    }

    /// Directories first, then files, each alphabetical — the order every file
    /// tree uses, and the one a reader scans fastest.
    static func sorted(_ entries: [HermesWorkspaceFileEntryDTO]) -> [HermesWorkspaceFileEntryDTO] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The parent of an absolute path, or nil at the root. Lets "go up" work
    /// without asking the server where it is.
    static func parentPath(_ path: String) -> String? {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, trimmed != "/" else { return nil }
        guard let cut = trimmed.lastIndex(of: "/") else { return nil }
        let parent = String(trimmed[trimmed.startIndex ..< cut])
        return parent.isEmpty ? "/" : parent
    }
}
