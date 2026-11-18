// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultViewTableModel.swift
// Backlog E8.5: a saved view's rows, read-only. Runs the view's query
// (POST /v1/vault/query), keeps the view's column order, and splits the rows
// into group sections where the group key changes. Editing is post-1.0.
import Foundation
import Observation

@MainActor
@Observable
final class VaultViewTableModel {
    struct Column: Equatable, Identifiable {
        let name: String
        let kind: VaultPropertyKind
        var id: String {
            name
        }
    }

    struct Section: Identifiable {
        /// nil when the view has no group.
        let title: String?
        let count: Int?
        let rows: [VaultQueryRow]
        let id: String
    }

    let view: VaultSavedView
    private let vaultClient: VaultClientProtocol
    private static let pageSize = 100

    private(set) var rows: [VaultQueryRow] = []
    private(set) var columns: [Column] = []
    private(set) var groups: [VaultQueryGroup] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    var error: String?

    init(view: VaultSavedView, vaultClient: VaultClientProtocol) {
        self.view = view
        self.vaultClient = vaultClient
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            let out = try await vaultClient.query(VaultQueryRequest(view: view, limit: Self.pageSize))
            rows = out.rows
            groups = out.groups ?? []
            nextCursor = out.nextCursor
            columns = Self.columns(present: out.columns, order: view.columns)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let out = try await vaultClient.query(VaultQueryRequest(view: view, limit: Self.pageSize, cursor: cursor))
            let seen = Set(rows.map(\.file.id))
            rows += out.rows.filter { !seen.contains($0.file.id) }
            nextCursor = out.nextCursor
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The view's order when it has one (a column left out is hidden), else
    /// every property present in scope, as the server lists them.
    static func columns(present: [VaultPropertyTypeDTO], order: [VaultViewColumn]) -> [Column] {
        guard !order.isEmpty else { return present.map { Column(name: $0.name, kind: $0.type) } }
        let byName = Dictionary(present.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        return order.map { c in
            Column(name: c.property, kind: byName[c.property] ?? VaultPropertyKind.reserved(c.property) ?? .text)
        }
    }

    var sections: [Section] {
        Self.sections(rows: rows, group: view.group, kind: groupKind, groups: groups)
    }

    private var groupKind: VaultPropertyKind {
        guard let group = view.group else { return .text }
        return columns.first { $0.name == group }?.kind ?? VaultPropertyKind.reserved(group) ?? .text
    }

    static func sections(
        rows: [VaultQueryRow],
        group: String?,
        kind: VaultPropertyKind,
        groups: [VaultQueryGroup]
    ) -> [Section] {
        guard let group, !group.isEmpty else {
            return rows.isEmpty ? [] : [Section(title: nil, count: nil, rows: rows, id: "all")]
        }
        var out: [Section] = []
        var current: [VaultQueryRow] = []
        var currentKey: String?
        var currentValue: VaultPropertyValue?

        func flush() {
            guard let key = currentKey, !current.isEmpty else { return }
            let isList = if case .list = currentValue {
                true
            } else {
                false
            }
            let count = isList ? nil : groups.first {
                VaultPropertyDisplay.groupKey($0.value, kind: kind) == key
            }?.count
            out.append(Section(
                title: VaultPropertyDisplay.groupLabel(currentValue, kind: kind),
                count: count,
                rows: current,
                id: "\(out.count):\(key)"
            ))
        }

        for row in rows {
            let value = row.properties[group]
            let key = VaultPropertyDisplay.groupKey(value, kind: kind)
            if key != currentKey {
                flush()
                current = []
                currentKey = key
                currentValue = value
            }
            current.append(row)
        }
        flush()
        return out
    }
}
