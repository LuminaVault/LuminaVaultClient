// LuminaVaultClient/LuminaVaultClient/Features/Settings/VaultImport/VaultImportViewModel.swift
//
// Import an Obsidian/Hermes vault folder into LuminaVault. Reads the picked
// folder locally (security-scoped), groups markdown by top folder → Space, and
// posts each in batches to /v1/import/vault-bulk. Content is read up-front while
// the security scope is held, so the later async upload needs no scope.

import Foundation
import Observation

@MainActor
@Observable
final class VaultImportViewModel {
    nonisolated struct FileRef: Identifiable, Sendable {
        let id = UUID()
        let relPath: String   // path within its top folder
        let content: String
    }

    nonisolated struct Folder: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let files: [FileRef]
        var count: Int { files.count }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case manifest
        case importing
        case done
        case failed(String)
    }

    var phase: Phase = .idle
    var folders: [Folder] = []
    var selected: Set<String> = []
    var progress: Double = 0
    var resultText: String = ""
    /// Leave a note that is already in LuminaVault under the same name as it
    /// is (`onConflict: skip`). Off replaces it with the vault's version.
    var keepExisting = true
    /// Server outcomes that need a look: kept notes, name clashes, failures.
    var needsAttention: [VaultBulkFileResult] = []

    /// What bulk import writes; anything else in a vault is an attachment.
    nonisolated static let noteExtensions: Set<String> = ["md", "markdown", "txt"]

    /// Skip absurdly large single files + cap how many per upload request.
    private let maxFileBytes = 1_000_000
    private let batchSize = 400

    private let client: VaultImportClientProtocol

    init(client: VaultImportClientProtocol) {
        self.client = client
    }

    var canImport: Bool {
        if case .manifest = phase { return !selected.isEmpty }
        return false
    }

    func toggle(_ name: String) {
        if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
    }

    /// Read + group the picked folder. Heavy file IO runs off the main actor.
    func scan(_ root: URL) async {
        phase = .scanning
        folders = []
        selected = []
        let maxBytes = maxFileBytes
        let grouped = await Task.detached {
            Self.groupMarkdown(in: root, maxBytes: maxBytes)
        }.value

        guard let grouped, !grouped.isEmpty else {
            phase = .failed("No readable .md files in that folder.")
            return
        }
        folders = grouped
        // Default-select everything except very large folders (likely noisy auto-files).
        selected = Set(grouped.filter { $0.count <= 1000 }.map(\.name))
        phase = .manifest
    }

    /// Walks `root` and groups its readable markdown by top folder.
    /// Synchronous: `NSEnumerator` cannot be iterated from an async context.
    nonisolated private static func groupMarkdown(in root: URL, maxBytes: Int) -> [Folder]? {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        // Hidden files and folders are app state (.obsidian, .trash, .git), not notes.
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var byTop: [String: [FileRef]] = [:]
        for case let url as URL in walker {
            guard noteExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let data = try? Data(contentsOf: url), data.count <= maxBytes,
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let rel = url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.lastPathComponent
            let comps = rel.split(separator: "/").map(String.init)
            let top = comps.count > 1 ? comps[0] : root.lastPathComponent
            let within = comps.count > 1 ? comps.dropFirst().joined(separator: "/") : rel
            byTop[top, default: []].append(FileRef(relPath: within, content: text))
        }
        return byTop.map { Folder(name: $0.key, files: $0.value) }.sorted { $0.count > $1.count }
    }

    func runImport() async {
        let chosen = folders.filter { selected.contains($0.name) }
        let total = chosen.reduce(0) { $0 + $1.count }
        guard total > 0 else { phase = .failed("Nothing selected."); return }
        phase = .importing
        progress = 0
        var imported = 0, skipped = 0, failed = 0, done = 0
        var kept = 0, clashes = 0
        needsAttention = []
        let onConflict = keepExisting ? "skip" : "overwrite"
        for folder in chosen {
            var index = 0
            while index < folder.files.count {
                let slice = folder.files[index ..< min(index + batchSize, folder.files.count)]
                let payload = slice.map { VaultBulkFile(path: $0.relPath, content: $0.content) }
                do {
                    let r = try await client.bulk(space: folder.name, files: payload, onConflict: onConflict)
                    imported += r.imported; skipped += r.skipped; failed += r.failed
                    for file in r.files ?? [] where ["exists", "collision", "failed"].contains(file.status) {
                        if file.status == "exists" { kept += 1 }
                        if file.status == "collision" { clashes += 1 }
                        needsAttention.append(file)
                    }
                } catch {
                    phase = .failed("Import failed: \(error.localizedDescription)")
                    return
                }
                index += batchSize
                done += payload.count
                progress = Double(done) / Double(total)
            }
        }
        var parts = ["Imported \(imported)"]
        if kept > 0 { parts.append("kept \(kept) existing") }
        if clashes > 0 { parts.append("\(clashes) name \(clashes == 1 ? "clash" : "clashes")") }
        let otherSkipped = skipped - kept - clashes
        if otherSkipped > 0 { parts.append("\(otherSkipped) already there or empty") }
        if failed > 0 { parts.append("failed \(failed)") }
        resultText = parts.joined(separator: " · ")
        phase = .done
    }
}
