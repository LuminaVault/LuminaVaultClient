// LuminaVaultClient/LuminaVaultClient/Features/Chat/Preview/ChatPreviewTarget.swift
//
// What the chat preview pane can show, and how each thing is addressed.
//
// One string addresses every target. It is the identity, the deep link and
// the dedupe key, so those can never drift apart. The format is one contract
// shared with the web client (`src/lib/chat/preview-target.ts`) and with any
// link either client emits — keep the two in step. The tests pin the exact
// strings for that reason.

import Foundation

enum ChatPreviewTarget: Hashable, Sendable, Identifiable {
    /// A harvested Hermes artifact.
    case artifact(id: String)
    /// A file in the user's vault, by tenant-relative path.
    case vaultFile(path: String)
    /// An external page. Shown as a link card, never navigated into.
    case url(URL)
    /// One persisted run event's output. No new storage: the row exists.
    case toolOutput(runID: String, seq: Int)

    private static let scheme = "lv://"

    var id: String { address }

    /// The address for a target. Stable, and safe in a query string.
    var address: String {
        switch self {
        case let .artifact(id):
            return Self.scheme + "artifact/" + Self.encode(id)
        case let .vaultFile(path):
            // Segments encoded one by one so slashes survive as structure.
            let encoded = path.split(separator: "/", omittingEmptySubsequences: false)
                .map { Self.encode(String($0)) }
                .joined(separator: "/")
            return Self.scheme + "vault/" + encoded
        case let .toolOutput(runID, seq):
            return Self.scheme + "run/" + Self.encode(runID) + "/event/\(seq)"
        case let .url(url):
            // A URL is its own address; wrapping it would give one page two
            // spellings and therefore two identities.
            return url.absoluteString
        }
    }

    /// Parses an address, or `nil` if it is not one. Never throws: addresses
    /// arrive from links and stored state, where a bad value should open
    /// nothing rather than fail.
    init?(address: String) {
        guard !address.isEmpty else { return nil }

        guard address.hasPrefix(Self.scheme) else {
            // Only http(s) is previewable. Anything else could be
            // `javascript:` or `data:`, which must never reach a renderer.
            guard let url = URL(string: address),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { return nil }
            self = .url(url)
            return
        }

        let segments = address.dropFirst(Self.scheme.count)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        switch segments.first {
        case "artifact" where segments.count == 2 && !segments[1].isEmpty:
            guard let id = segments[1].removingPercentEncoding else { return nil }
            self = .artifact(id: id)
        case "vault" where segments.count > 1:
            let decoded = segments.dropFirst().compactMap { $0.removingPercentEncoding }
            guard decoded.count == segments.count - 1 else { return nil }
            let path = decoded.joined(separator: "/")
            guard !path.isEmpty else { return nil }
            self = .vaultFile(path: path)
        case "run" where segments.count == 4 && segments[2] == "event":
            // Digits only: `Int("")` is nil here, but `+1` and `-1` parse, and
            // neither is a sequence number.
            guard !segments[1].isEmpty,
                  !segments[3].isEmpty,
                  segments[3].allSatisfy(\.isASCII),
                  segments[3].allSatisfy(\.isNumber),
                  let seq = Int(segments[3]),
                  let runID = segments[1].removingPercentEncoding
            else { return nil }
            self = .toolOutput(runID: runID, seq: seq)
        default:
            return nil
        }
    }

    /// A short label for a chip or a pane header.
    var label: String {
        switch self {
        case .artifact: "Artifact"
        case let .vaultFile(path): path.split(separator: "/").last.map(String.init) ?? path
        case .toolOutput: "Tool output"
        case let .url(url): url.host() ?? url.absoluteString
        }
    }

    /// Matches `encodeURIComponent`, so both clients produce identical
    /// addresses for the same target.
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
