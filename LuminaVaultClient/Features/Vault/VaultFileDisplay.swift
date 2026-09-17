// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultFileDisplay.swift
//
// How a vault file reads to a person.
//
// `VaultFileDTO` carries a path, a content type, a size and a little note
// metadata — no excerpt, no preview. So everything human about a row is
// derived here, in one place, rather than in each list that draws one.

import Foundation
import LuminaVaultShared

enum VaultFileDisplay {
    /// The best title available, in order of how much we actually know:
    /// the file's own title, then the host of a link still being fetched,
    /// then the capture date for a note the user never named, then the
    /// filename tidied up.
    static func title(for file: VaultFileDTO) -> String {
        if let title = file.metadata?.title, !title.isEmpty {
            return title
        }

        let basename = (file.path as NSString).lastPathComponent
        let stem = (basename as NSString).deletingPathExtension

        if isEnriching(file), let host = host(fromCaptureStem: stem) {
            return host
        }

        if isBareUUID(stem) {
            guard let createdAt = file.createdAt else { return "Note" }
            return "Note · " + createdAt.formatted(noteDateStyle)
        }

        return humanised(stem)
    }

    /// When it arrived, and where it went. Not the path and not the byte
    /// count: neither tells you anything you were looking for in a list of
    /// things you saved.
    static func subtitle(for file: VaultFileDTO, spaceName: String?, now: Date = .now) -> String {
        // A link is written as a placeholder and rewritten once the server
        // has fetched the page. Saying so is the difference between a row
        // that looks broken and one that is visibly still arriving.
        if isEnriching(file) { return "Fetching the page…" }

        let relative = file.createdAt.map { relativeDescription(of: $0, to: now) }
        return [relative, spaceName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// What kind of thing this is, at a glance.
    static func symbolName(for file: VaultFileDTO) -> String {
        if file.metadata?.enrichmentStatus != nil { return "link" }
        if file.contentType.hasPrefix("image/") { return "photo" }
        if file.contentType.hasPrefix("text/") || file.path.hasSuffix(".md") { return "doc.text" }
        return "paperclip"
    }

    // MARK: - Heuristics

    private static func isEnriching(_ file: VaultFileDTO) -> Bool {
        file.metadata?.enrichmentStatus == "pending"
    }

    /// A captured link is stored as `<stamp>-<host>-<uuid8>.md`, where the
    /// stamp is `YYYY-MM-DD-HHmmss` and the host's dots were flattened to
    /// hyphens — `2026-09-14-161709-kheprios-com-00e2c497.md` is
    /// `kheprios.com`. Reversing that means joining the middle segments with
    /// dots, which cannot distinguish a dot from a hyphen that was always a
    /// hyphen: `my-site.com` comes back as `my.site.com`. That is wrong for
    /// the minority of hosts containing a hyphen and right for the rest, and
    /// it only shows for the seconds before enrichment writes a real title.
    private static func host(fromCaptureStem stem: String) -> String? {
        let segments = stem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // 4 stamp segments + at least one host segment + the uuid8.
        guard segments.count >= 6 else { return nil }
        guard segments[0].count == 4, segments[0].allSatisfy(\.isNumber),
              segments[1].count == 2, segments[1].allSatisfy(\.isNumber),
              segments[2].count == 2, segments[2].allSatisfy(\.isNumber),
              segments[3].count == 6, segments[3].allSatisfy(\.isNumber),
              isShortHex(segments[segments.count - 1])
        else { return nil }
        return segments[4..<(segments.count - 1)].joined(separator: ".")
    }

    /// A note saved from the composer is named for its queue id alone, so
    /// there is nothing in the filename to show anybody.
    private static func isBareUUID(_ stem: String) -> Bool {
        UUID(uuidString: stem) != nil
    }

    private static func isShortHex(_ segment: String) -> Bool {
        segment.count == 8 && segment.allSatisfy(\.isHexDigit)
    }

    /// Filename → sentence: drop a leading capture stamp and a trailing
    /// uuid8, then read the hyphens as the spaces they stand in for.
    private static func humanised(_ stem: String) -> String {
        var segments = stem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if segments.count >= 5,
           segments[0].count == 4, segments[0].allSatisfy(\.isNumber),
           segments[1].count == 2, segments[1].allSatisfy(\.isNumber),
           segments[2].count == 2, segments[2].allSatisfy(\.isNumber),
           segments[3].count == 6, segments[3].allSatisfy(\.isNumber)
        {
            segments.removeFirst(4)
        }
        if segments.count > 1, let last = segments.last, isShortHex(last) {
            segments.removeLast()
        }
        let words = segments.filter { !$0.isEmpty }.joined(separator: " ")
        guard let first = words.first else { return stem }
        return first.uppercased() + words.dropFirst()
    }

    // MARK: - Dates

    /// `d MMM, HH:mm` in spirit, laid out the way the reader's locale does it.
    private static var noteDateStyle: Date.FormatStyle {
        Date.FormatStyle()
            .day()
            .month(.abbreviated)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute()
    }

    /// "2 days ago", "yesterday". `RelativeDateTimeFormatter` rather than
    /// `.relative(presentation: .named)` because only it takes the reference
    /// date, which is what makes this testable against a fixed `now`.
    private static func relativeDescription(of date: Date, to now: Date) -> String {
        // Built per call: the formatter is not `Sendable`, so hoisting it into
        // a `static let` would need an isolation exemption for a saving that
        // never shows on a list of this size.
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
