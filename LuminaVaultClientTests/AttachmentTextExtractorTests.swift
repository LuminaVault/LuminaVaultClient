// LuminaVaultClient/LuminaVaultClientTests/AttachmentTextExtractorTests.swift
//
// Unit tests for client-side file → text extraction used by the chat
// composer. Covers plain text / markdown reads, PDF extraction (synthed
// via UIGraphicsPDFRenderer), truncation, and the error cases.
import Testing
import Foundation
import UIKit
@testable import LuminaVaultClient

struct AttachmentTextExtractorTests {

    // MARK: - Helpers

    /// Writes `content` to a temp file with `ext` and returns its URL.
    private func tempFile(_ content: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    /// Synthesizes a single-page PDF containing `text` and returns its URL.
    private func tempPDF(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            (text as NSString).draw(
                at: CGPoint(x: 40, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
        try data.write(to: url)
        return url
    }

    // MARK: - Plain text / markdown

    @Test func extractsPlainText() throws {
        let url = try tempFile("Hello vault", ext: "txt")
        let result = try AttachmentTextExtractor.extract(from: url)
        #expect(result.text == "Hello vault")
        #expect(result.name == url.lastPathComponent)
    }

    @Test func extractsMarkdownAndTrims() throws {
        let url = try tempFile("\n\n# Heading\n\nBody\n\n", ext: "md")
        let result = try AttachmentTextExtractor.extract(from: url)
        #expect(result.text == "# Heading\n\nBody")
    }

    // MARK: - PDF

    @Test func extractsPDFText() throws {
        let url = try tempPDF("Quarterly report figures")
        let result = try AttachmentTextExtractor.extract(from: url)
        #expect(result.text.contains("Quarterly report figures"))
    }

    // MARK: - Truncation

    @Test func truncatesOverBudget() throws {
        let big = String(repeating: "a", count: AttachmentTextExtractor.maxCharacters + 500)
        let url = try tempFile(big, ext: "txt")
        let result = try AttachmentTextExtractor.extract(from: url)
        #expect(result.text.hasSuffix("…[truncated]"))
        #expect(result.text.count <= AttachmentTextExtractor.maxCharacters + 20)
    }

    // MARK: - Errors

    @Test func rejectsUnsupportedType() throws {
        let url = try tempFile("not really an image", ext: "png")
        #expect(throws: AttachmentTextExtractor.ExtractionError.self) {
            try AttachmentTextExtractor.extract(from: url)
        }
    }

    @Test func rejectsEmptyFile() throws {
        let url = try tempFile("   \n\t ", ext: "txt")
        #expect(throws: AttachmentTextExtractor.ExtractionError.self) {
            try AttachmentTextExtractor.extract(from: url)
        }
    }
}
