// LuminaVaultClient/LuminaVaultClient/Features/Chat/AttachmentTextExtractor.swift
//
// Client-side file → text extraction for the chat composer. There is no
// per-message attachment contract on the server (the SSE message stream
// carries `content` only), so a picked file rides into the conversation
// as plain text prepended to the user's turn. `.txt` / `.md` are read
// directly; `.pdf` goes through PDFKit. Images / binaries are rejected
// with a user-facing message.
import Foundation
import PDFKit

enum AttachmentTextExtractor {
    /// Max characters of extracted text injected into a prompt. Protects
    /// the context window from a large PDF dumping thousands of tokens
    /// into a single turn.
    static let maxCharacters = 8_000

    /// Plain-text payload extracted from a picked file.
    struct Extracted: Equatable, Sendable {
        let name: String
        let text: String
    }

    enum ExtractionError: LocalizedError {
        case unreadable
        case unsupportedType(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Couldn't read that file."
            case .unsupportedType(let ext):
                let label = ext.isEmpty ? "That type" : ".\(ext)"
                return "\(label) isn't supported yet — pick a .txt, .md, or .pdf."
            case .empty:
                return "That file has no extractable text."
            }
        }
    }

    /// Reads a security-scoped URL (from `.fileImporter`) and returns its
    /// plain-text content, trimmed and truncated to `maxCharacters`.
    static func extract(from url: URL) throws -> Extracted {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let raw: String
        switch ext {
        case "txt", "md", "markdown", "text", "":
            guard let data = try? Data(contentsOf: url),
                  let string = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            else {
                throw ExtractionError.unreadable
            }
            raw = string
        case "pdf":
            guard let doc = PDFDocument(url: url) else {
                throw ExtractionError.unreadable
            }
            raw = doc.string ?? ""
        default:
            throw ExtractionError.unsupportedType(ext)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExtractionError.empty }

        let clipped = trimmed.count > maxCharacters
            ? String(trimmed.prefix(maxCharacters)) + "\n…[truncated]"
            : trimmed
        return Extracted(name: name, text: clipped)
    }
}
