import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class MarkdownNoteImporterTests: XCTestCase {
    func testNoteNameKeepsANameTheServerAccepts() {
        XCTAssertEqual(
            MarkdownNoteImporter.noteName("The_Last_Light_Universe_Bible_v0.1.md"),
            "The_Last_Light_Universe_Bible_v0.1.md"
        )
        XCTAssertEqual(MarkdownNoteImporter.noteName("café.md"), "café.md")
    }

    func testNoteNameReplacesWhatSanitizePathRefuses() {
        XCTAssertEqual(MarkdownNoteImporter.noteName("My Note [draft].md"), "My-Note-draft.md")
        XCTAssertEqual(MarkdownNoteImporter.noteName("Plans 🚀 2027.markdown"), "Plans-2027.markdown")
        XCTAssertEqual(MarkdownNoteImporter.noteName("README.MD"), "README.md")
        XCTAssertEqual(MarkdownNoteImporter.noteName(".hidden.md"), "hidden.md")
        XCTAssertEqual(MarkdownNoteImporter.noteName("🚀.md"), "note.md")
    }

    func testNoteNameAddsASuffixOnLaterAttempts() {
        XCTAssertEqual(MarkdownNoteImporter.noteName("Lore.md", attempt: 2), "Lore-2.md")
    }

    func testIsTextNote() {
        XCTAssertTrue(MarkdownNoteImporter.isTextNote(URL(fileURLWithPath: "/a/b.md")))
        XCTAssertTrue(MarkdownNoteImporter.isTextNote(URL(fileURLWithPath: "/a/b.TXT")))
        XCTAssertFalse(MarkdownNoteImporter.isTextNote(URL(fileURLWithPath: "/a/b.pdf")))
    }

    func testImportWritesACreateOnlyNoteUnderTheFileName() async throws {
        let uploader = TakenNamesUploader(taken: [])
        let note = try await MarkdownNoteImporter(uploader: uploader)
            .importNote(data: Data("# Lore".utf8), fileName: "Lore.md", spaceID: nil)

        XCTAssertEqual(note, ImportedNote(fileName: "Lore.md", path: "inbox/Lore.md", renamed: false))
        let calls = await uploader.calls
        XCTAssertEqual(calls.map(\.path), ["inbox/Lore.md"])
        XCTAssertEqual(calls.first?.contentType, "text/markdown")
    }

    func testImportTriesTheNextSuffixWhenTheNameIsTaken() async throws {
        let uploader = TakenNamesUploader(taken: ["inbox/Lore.md", "inbox/Lore-2.md"])
        let note = try await MarkdownNoteImporter(uploader: uploader)
            .importNote(data: Data("x".utf8), fileName: "Lore.md", spaceID: nil)

        XCTAssertEqual(note.path, "inbox/Lore-3.md")
        XCTAssertTrue(note.renamed)
        let paths = await uploader.calls.map(\.path)
        XCTAssertEqual(paths, ["inbox/Lore.md", "inbox/Lore-2.md", "inbox/Lore-3.md"])
    }

    func testImportSurfacesOtherFailuresWithoutRenaming() async {
        let uploader = TakenNamesUploader(taken: [], failWith: 400)
        do {
            _ = try await MarkdownNoteImporter(uploader: uploader)
                .importNote(data: Data("x".utf8), fileName: "Lore.md", spaceID: nil)
            XCTFail("expected a throw")
        } catch let APIError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 400)
        } catch {
            XCTFail("unexpected \(error)")
        }
        let count = await uploader.calls.count
        XCTAssertEqual(count, 1)
    }
}

/// Answers `createNote` with 412 for any path already in `taken`, the way the
/// server answers `If-None-Match: *`.
actor TakenNamesUploader: VaultUploadClientProtocol {
    struct Call: Sendable {
        let path: String
        let contentType: String
    }

    private(set) var calls: [Call] = []
    private let taken: Set<String>
    private let failWith: Int?

    init(taken: Set<String>, failWith: Int? = nil) {
        self.taken = taken
        self.failWith = failWith
    }

    func createNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID _: UUID?
    ) async throws -> VaultUploadResponse {
        calls.append(Call(path: relativePath, contentType: contentType))
        if let failWith {
            throw APIError.httpError(statusCode: failWith, data: Data())
        }
        if taken.contains(relativePath) {
            throw APIError.httpError(statusCode: 412, data: Data())
        }
        return VaultUploadResponse(path: relativePath, size: data.count, contentType: contentType, sha256: "")
    }

    func uploadAsset(
        data _: Data,
        contentType _: String,
        relativePath _: String,
        spaceID _: UUID?
    ) async throws -> VaultUploadResponse {
        throw APIError.unauthorized
    }

    func uploadNote(
        data _: Data, contentType _: String, relativePath _: String,
        spaceID _: UUID?, metadata _: VaultNoteMetadataDTO?
    ) async throws -> VaultUploadResponse {
        throw APIError.unauthorized
    }
}
