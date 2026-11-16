import Foundation
import LuminaVaultShared
import UniformTypeIdentifiers

/// What an imported markdown or text file became.
nonisolated struct ImportedNote: Equatable, Sendable {
    let fileName: String
    /// The vault path the server wrote, `inbox/<name>` or `<space>/<name>`.
    let path: String
    /// True when the stored name differs from the file's own name.
    let renamed: Bool
}

/// Imports `.md`, `.markdown` and `.txt` files as notes.
///
/// Hermes ingestion refuses `text/markdown` (the item ends
/// `blocked_capability`), so text files skip it and go straight to
/// `POST /v1/vault/files?note=true`: the server writes the memory, embedding,
/// chunks and wikilinks in that call. The file keeps its own name, made legal
/// for the server's `SanitizePath`, and the write is create-only, so a name
/// that is already taken gets a `-2`, `-3`, ... suffix instead of replacing
/// that note. Mirrors `importTextNote` on the web.
nonisolated struct MarkdownNoteImporter: Sendable {
    static let textExtensions: Set<String> = ["md", "markdown", "txt"]
    static let maxAttempts = 20

    /// The types the capture file picker adds for text notes.
    static let contentTypes: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        .plainText,
    ]

    let uploader: any VaultUploadClientProtocol

    static func isTextNote(_ url: URL) -> Bool {
        textExtensions.contains(url.pathExtension.lowercased())
    }

    /// The server's `SanitizePath` allows letters, marks, numbers, `.`, `_`
    /// and `-` in a segment and refuses anything else with a 400, so every
    /// other run of characters becomes one `-`. `attempt` > 1 adds a suffix.
    static func noteName(_ fileName: String, attempt: Int = 1) -> String {
        let url = URL(fileURLWithPath: fileName)
        let rawExtension = url.pathExtension
        let ext = rawExtension.isEmpty ? "md" : rawExtension.lowercased()
        let base = rawExtension.isEmpty ? fileName : String(fileName.dropLast(rawExtension.count + 1))

        var stem = ""
        var lastWasDash = false
        for scalar in base.precomposedStringWithCanonicalMapping.unicodeScalars {
            if isAllowed(scalar) {
                stem.unicodeScalars.append(scalar)
                lastWasDash = scalar == "-"
            } else if !lastWasDash {
                stem.append("-")
                lastWasDash = true
            }
        }
        let trim: (Character) -> Bool = { $0 == "-" || $0 == "." }
        stem = String(stem.drop(while: trim))
        while let last = stem.last, trim(last) {
            stem.removeLast()
        }
        stem = String(stem.prefix(120))
        while let last = stem.last, trim(last) {
            stem.removeLast()
        }
        if stem.isEmpty {
            stem = "note"
        }
        return attempt > 1 ? "\(stem)-\(attempt).\(ext)" : "\(stem).\(ext)"
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "." || scalar == "_" || scalar == "-" {
            return true
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    func importNote(data: Data, fileName: String, spaceID: UUID?) async throws -> ImportedNote {
        let contentType = URL(fileURLWithPath: fileName).pathExtension.lowercased() == "txt"
            ? "text/plain" : "text/markdown"
        for attempt in 1 ... Self.maxAttempts {
            let name = Self.noteName(fileName, attempt: attempt)
            do {
                let response = try await uploader.createNote(
                    data: data, contentType: contentType,
                    relativePath: "inbox/\(name)", spaceID: spaceID
                )
                return ImportedNote(fileName: fileName, path: response.path, renamed: name != fileName)
            } catch let APIError.httpError(statusCode, _) where statusCode == 412 {
                continue
            }
        }
        throw ImportError.namesExhausted(fileName)
    }

    func importNote(fileURL: URL, spaceID: UUID?) async throws -> ImportedNote {
        let granted = fileURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: fileURL)
        return try await importNote(data: data, fileName: fileURL.lastPathComponent, spaceID: spaceID)
    }

    enum ImportError: LocalizedError {
        case namesExhausted(String)

        var errorDescription: String? {
            switch self {
            case let .namesExhausted(name):
                "\(name): every name up to -\(MarkdownNoteImporter.maxAttempts) is already taken."
            }
        }
    }
}
