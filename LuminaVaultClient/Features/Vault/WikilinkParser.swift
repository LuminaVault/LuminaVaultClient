// LuminaVaultClient/LuminaVaultClient/Features/Vault/WikilinkParser.swift
// Obsidian-compatible [[note]] and [[memory:<uuid>]] parsing for reader-only
// rendering. Stored Markdown remains unchanged.

import Foundation

struct Wikilink: Equatable, Identifiable {
    enum Kind: Equatable {
        case note(String)
        case memory(UUID)
    }

    let id = UUID()
    let rawTarget: String
    let label: String
    let kind: Kind
}

enum WikilinkParser {
    static let urlScheme = "luminavault-wikilink"

    static func links(in markdown: String) -> [Wikilink] {
        matches(in: markdown).compactMap { parseBody(String(markdown[$0.bodyRange])) }
    }

    static func markdownByRenderingLinks(in markdown: String) -> String {
        var rendered = markdown
        for match in matches(in: markdown).reversed() {
            guard let link = parseBody(String(markdown[match.bodyRange])),
                  let replacement = markdownLink(for: link)
            else { continue }
            rendered.replaceSubrange(match.fullRange, with: replacement)
        }
        return rendered
    }

    static func link(from url: URL) -> Wikilink? {
        guard url.scheme == urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let target = components.queryItems?.first(where: { $0.name == "target" })?.value,
              let label = components.queryItems?.first(where: { $0.name == "label" })?.value
        else { return nil }

        switch host {
        case "note":
            return parseNote(target: target, label: label)
        case "memory":
            return parseMemory(target: target, label: label)
        default:
            return nil
        }
    }

    private struct Match {
        let fullRange: Range<String.Index>
        let bodyRange: Range<String.Index>
    }

    private static func matches(in text: String) -> [Match] {
        var matches: [Match] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let start = text[cursor...].range(of: "[[")?.lowerBound else { break }
            let bodyStart = text.index(start, offsetBy: 2)
            guard let end = text[bodyStart...].range(of: "]]")?.lowerBound else { break }
            let fullEnd = text.index(end, offsetBy: 2)
            matches.append(Match(fullRange: start ..< fullEnd, bodyRange: bodyStart ..< end))
            cursor = fullEnd
        }
        return matches
    }

    private static func parseBody(_ body: String) -> Wikilink? {
        let pieces = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let targetPiece = pieces.first else { return nil }
        let target = String(targetPiece).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        let alias = pieces.count > 1
            ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let label = alias.isEmpty ? defaultLabel(for: target) : alias

        if target.lowercased().hasPrefix("memory:") {
            let rawID = String(target.dropFirst("memory:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return parseMemory(target: rawID, label: label)
        }
        return parseNote(target: target, label: label)
    }

    private static func parseNote(target: String, label: String) -> Wikilink? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Wikilink(rawTarget: trimmed, label: label, kind: .note(trimmed))
    }

    private static func parseMemory(target: String, label: String) -> Wikilink? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmed) else { return nil }
        return Wikilink(rawTarget: trimmed, label: label, kind: .memory(id))
    }

    private static func defaultLabel(for target: String) -> String {
        if target.lowercased().hasPrefix("memory:") {
            return "Memory"
        }
        return target
    }

    private static func markdownLink(for link: Wikilink) -> String? {
        var components = URLComponents()
        components.scheme = urlScheme
        switch link.kind {
        case .note:
            components.host = "note"
        case .memory:
            components.host = "memory"
        }
        components.queryItems = [
            URLQueryItem(name: "target", value: link.rawTarget),
            URLQueryItem(name: "label", value: link.label),
        ]
        guard let url = components.url?.absoluteString else { return nil }
        return "[\(escapeMarkdownLabel(link.label))](\(url))"
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
