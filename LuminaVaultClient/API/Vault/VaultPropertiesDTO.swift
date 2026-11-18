// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultPropertiesDTO.swift
// Backlog E8.5: note properties and saved views, read-only on iOS (spec
// 2026-11-16, D6/D7). Mirrors the Go spec's VaultPropertyType, the
// `properties`/`propertiesError` fields of VaultFileDTO, VaultView and
// VaultQueryRequest/Response. Client-local like the other Go-era vault DTOs
// (history, trash, links): LuminaVaultShared mirrors the archived Swift
// server, which never had these routes.
//
// Property names are the note's own frontmatter keys. `JSONDecoder.hvDefault`
// converts struct keys from snake_case but leaves `[String: …]` dictionary
// keys alone, so `date_created` stays `date_created` (pinned by a test).
import Foundation
import LuminaVaultShared

/// One frontmatter value as the server normalised it: a scalar, a list, or
/// (rarely, for YAML the registry doesn't type) a map.
nonisolated enum VaultPropertyValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([VaultPropertyValue])
    case map([String: VaultPropertyValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null; return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b); return
        }
        if let n = try? c.decode(Double.self) {
            self = .number(n); return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s); return
        }
        if let l = try? c.decode([VaultPropertyValue].self) {
            self = .list(l); return
        }
        self = try .map(c.decode([String: VaultPropertyValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(n): try c.encode(n)
        case let .bool(b): try c.encode(b)
        case let .list(l): try c.encode(l)
        case let .map(m): try c.encode(m)
        case .null: try c.encodeNil()
        }
    }

    var isEmpty: Bool {
        switch self {
        case .null: true
        case let .string(s): s.isEmpty
        case let .list(l): l.isEmpty
        default: false
        }
    }

    /// The items of a list (multiselect, tags); a scalar is one item.
    var items: [VaultPropertyValue] {
        if case let .list(l) = self {
            return l
        }
        return isEmpty ? [] : [self]
    }

    var stringValue: String? {
        if case let .string(s) = self {
            return s
        }
        return nil
    }
}

/// The type a vault gives a property name (D3). Unknown future types read as text.
nonisolated enum VaultPropertyKind: String, Codable, Sendable, CaseIterable {
    case text, number, select, multiselect, date, datetime, checkbox, url

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VaultPropertyKind(rawValue: raw) ?? .text
    }

    /// Names whose type the server fixes, whatever the registry says.
    static func reserved(_ name: String) -> VaultPropertyKind? {
        switch name.lowercased() {
        case "title": .text
        case "tags": .multiselect
        case "due": .date
        case "done": .checkbox
        default: nil
        }
    }
}

nonisolated struct VaultPropertyTypeDTO: Codable, Sendable, Equatable {
    let name: String
    let type: VaultPropertyKind
    let options: [String]?

    init(name: String, type: VaultPropertyKind, options: [String]? = nil) {
        self.name = name
        self.type = type
        self.options = options
    }
}

nonisolated struct VaultPropertyTypesResponse: Decodable, Sendable, Equatable {
    let types: [VaultPropertyTypeDTO]
}

/// The registry, case-insensitive like the server's.
nonisolated struct VaultPropertyTypes: Sendable, Equatable {
    private let byName: [String: VaultPropertyKind]

    init(_ list: [VaultPropertyTypeDTO]) {
        var map: [String: VaultPropertyKind] = [:]
        for t in list {
            map[t.name.lowercased()] = t.type
        }
        byName = map
    }

    func kind(of name: String) -> VaultPropertyKind {
        VaultPropertyKind.reserved(name) ?? byName[name.lowercased()] ?? .text
    }
}

/// The two Go-only fields of a listed file. `VaultFileDTO` (Shared) has no
/// room for them, so the reader decodes the same list response again for
/// just these.
nonisolated struct VaultFileProperties: Decodable, Sendable, Equatable {
    let path: String
    let properties: [String: VaultPropertyValue]?
    let propertiesError: String?
}

nonisolated struct VaultFilePropertiesListResponse: Decodable, Sendable {
    let files: [VaultFileProperties]
}

// MARK: - Query and saved views

nonisolated struct VaultQueryScope: Codable, Sendable, Equatable {
    var spaceId: String?
    var folder: String?
    var tag: String?
}

nonisolated struct VaultQueryFilter: Codable, Sendable, Equatable {
    let property: String
    let op: String
    let value: VaultPropertyValue?
}

nonisolated struct VaultQuerySort: Codable, Sendable, Equatable {
    let property: String
    let dir: String
}

nonisolated struct VaultViewColumn: Codable, Sendable, Equatable {
    let property: String
    let width: Int?
}

nonisolated struct VaultSavedView: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let scope: VaultQueryScope
    let columns: [VaultViewColumn]
    let filter: [VaultQueryFilter]
    let sort: [VaultQuerySort]
    let group: String?
}

nonisolated struct VaultViewsResponse: Decodable, Sendable {
    let views: [VaultSavedView]
}

/// Sent as written: the Go decoder matches camelCase keys exactly.
nonisolated struct VaultQueryRequest: Encodable, Sendable, Equatable {
    let scope: VaultQueryScope
    let filter: [VaultQueryFilter]?
    let sort: [VaultQuerySort]?
    let group: String?
    let limit: Int
    let cursor: String?

    init(view: VaultSavedView, limit: Int = 100, cursor: String? = nil) {
        scope = view.scope
        filter = view.filter.isEmpty ? nil : view.filter
        sort = view.sort.isEmpty ? nil : view.sort
        group = (view.group?.isEmpty ?? true) ? nil : view.group
        self.limit = limit
        self.cursor = cursor
    }
}

nonisolated struct VaultQueryRow: Decodable, Sendable {
    let file: VaultFileDTO
    let properties: [String: VaultPropertyValue]
}

nonisolated struct VaultQueryGroup: Decodable, Sendable, Equatable {
    let value: VaultPropertyValue?
    let count: Int
}

nonisolated struct VaultQueryResponse: Decodable, Sendable {
    let rows: [VaultQueryRow]
    let columns: [VaultPropertyTypeDTO]
    let groups: [VaultQueryGroup]?
    let nextCursor: String?
}
