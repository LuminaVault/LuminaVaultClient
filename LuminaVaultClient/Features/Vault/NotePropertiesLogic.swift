// LuminaVaultClient/LuminaVaultClient/Features/Vault/NotePropertiesLogic.swift
// Backlog E8.5: what the read-only properties section and table show. Pure,
// so the tests cover it without a view.
import Foundation

nonisolated enum NoteFrontmatter {
    /// The note without its leading `---` block, for the rendered view: the
    /// properties section shows that block instead. Text without a closed
    /// block comes back unchanged. Same rule as the web (`stripFrontmatter`).
    static func strip(_ text: String) -> String {
        var body = text
        if body.hasPrefix("\u{FEFF}") {
            body.removeFirst()
        }
        // Foundation splits by UTF-16, so CRLF files split too: in Swift
        // "\r\n" is one Character and `split(separator: "\n")` misses it.
        let lines = body.components(separatedBy: "\n")
        func bare(_ line: String) -> String {
            line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
        }
        guard let first = lines.first, bare(first) == "---" else { return text }
        for index in lines.indices.dropFirst() where bare(lines[index]) == "---" || bare(lines[index]) == "..." {
            let rest = lines[(index + 1)...].joined(separator: "\n")
            return String(rest.drop(while: \.isNewline))
        }
        return text
    }
}

nonisolated enum VaultPropertyDisplay {
    /// One value as a line of text for its type.
    static func text(_ value: VaultPropertyValue, kind: VaultPropertyKind) -> String {
        switch value {
        case .null:
            return ""
        case let .bool(b):
            return b ? "Yes" : "No"
        case let .number(n):
            return number(n)
        case let .string(s):
            return string(s, kind: kind)
        case let .list(items):
            return items.map { text($0, kind: .text) }.joined(separator: ", ")
        case let .map(m):
            return m.keys.sorted().map { "\($0): \(text(m[$0] ?? .null, kind: .text))" }.joined(separator: ", ")
        }
    }

    private static func number(_ n: Double) -> String {
        if n.rounded() == n, abs(n) < 1e15 {
            return String(Int64(n))
        }
        return String(n)
    }

    private static func string(_ s: String, kind: VaultPropertyKind) -> String {
        switch kind {
        case .date:
            guard let date = dayFormatter.date(from: String(s.prefix(10))) else { return s }
            return date.formatted(date: .abbreviated, time: .omitted)
        case .datetime:
            guard let date = ISO8601DateFormatter().date(from: s) else { return s }
            return date.formatted(date: .abbreviated, time: .shortened)
        default:
            return s
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// An http(s) link for a url property, else nil (never `javascript:`).
    static func link(_ value: VaultPropertyValue) -> URL? {
        guard let s = value.stringValue, let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// Group key: the server orders rows by the group first, so a header goes
    /// wherever the key changes. A date groups by day; empty values together.
    static func groupKey(_ value: VaultPropertyValue?, kind: VaultPropertyKind) -> String {
        guard let value, !value.isEmpty else { return "" }
        if case let .string(s) = value, kind == .date || kind == .datetime {
            return String(s.prefix(10))
        }
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func groupLabel(_ value: VaultPropertyValue?, kind: VaultPropertyKind) -> String {
        guard let value, !value.isEmpty else { return "No value" }
        return text(value, kind: kind)
    }
}

/// One property of a note, ready to draw.
nonisolated struct NotePropertyRow: Equatable, Identifiable, Sendable {
    let name: String
    let kind: VaultPropertyKind
    let value: VaultPropertyValue
    var id: String {
        name
    }

    /// The note's properties sorted by name, the server's order; `title` is
    /// left out because the reader shows it as the heading.
    static func rows(_ properties: [String: VaultPropertyValue], types: VaultPropertyTypes) -> [NotePropertyRow] {
        properties.keys
            .filter { $0.lowercased() != "title" }
            .sorted()
            .map { NotePropertyRow(name: $0, kind: types.kind(of: $0), value: properties[$0] ?? .null) }
    }
}
