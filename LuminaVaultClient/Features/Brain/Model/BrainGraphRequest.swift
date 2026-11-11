// Request value for GET /v1/brain/graph. A port of `graphQuery` in the web
// app's `brain-api.ts`: parameter order and encoding match it exactly so both
// clients hit the same server cache keys.

import Foundation
import LuminaVaultShared

nonisolated struct BrainGraphRequest: Equatable, Sendable {
    /// `nil` (or an empty list) means every vault the user can see.
    var vaults: [UUID]?
    var focus: String?
    /// Clamped to `1...3` on init and on read.
    var depth: Int {
        get { Self.clamp(storedDepth) }
        set { storedDepth = Self.clamp(newValue) }
    }
    var similar: Bool

    private var storedDepth: Int

    static let unfocusedLimit = 800

    init(vaults: [UUID]? = nil, focus: String? = nil, depth: Int = 1, similar: Bool = false) {
        self.vaults = vaults
        self.focus = focus
        self.storedDepth = Self.clamp(depth)
        self.similar = similar
    }

    /// An author hub can hold everything a person wrote, so its graph is
    /// capped by `limit` and one step deep instead.
    static func isAuthorFocus(_ focus: String?) -> Bool {
        focus?.hasPrefix("author:") ?? false
    }

    /// `/v1/brain/graph?...`. `similar` is requested only when asked for. A
    /// focused request omits `author` unless the focus is an author hub (the
    /// server would 404 otherwise). Unfocused and author-focused requests are
    /// capped by `limit`; any other focused one is bounded by `depth`.
    var query: String {
        let isFocused = !(focus ?? "").isEmpty
        let isAuthor = isFocused && Self.isAuthorFocus(focus)
        let links = BrainLinkKindDTO.allCases.filter { kind in
            if kind == .similar { return similar }
            return !(isFocused && !isAuthor && kind == .author)
        }
        var pairs: [(String, String)] = [("links", links.map(\.rawValue).joined(separator: ","))]
        if isFocused, let focus {
            pairs.append(("focus", focus))
            pairs.append(("depth", String(isAuthor ? 1 : depth)))
        }
        if !isFocused || isAuthor {
            pairs.append(("limit", String(Self.unfocusedLimit)))
        }
        if let vaults, !vaults.isEmpty {
            pairs.append(("vaults", vaults.map { $0.uuidString.uppercased() }.joined(separator: ",")))
        }
        let encoded = pairs.map { "\($0.0)=\(Self.formEncode($0.1))" }.joined(separator: "&")
        return "/v1/brain/graph?\(encoded)"
    }

    private static func clamp(_ depth: Int) -> Int { min(3, max(1, depth)) }

    /// application/x-www-form-urlencoded, as `URLSearchParams` writes it:
    /// everything but ASCII letters, digits and `*-._` is percent-encoded and
    /// a space becomes `+`.
    private static func formEncode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                out.append(Character(UnicodeScalar(byte)))
            case UInt8(ascii: " "):
                out.append("+")
            default:
                out.append(String(format: "%%%02X", byte))
            }
        }
        return out
    }
}
