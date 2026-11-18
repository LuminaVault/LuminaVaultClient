// LuminaVaultClient/LuminaVaultClientTests/VaultUploadHTTPClientTests.swift
//
// HER-34 — assert HEIC + JPEG content-type passthrough and the
// query-param-encoded vault path.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class VaultUploadHTTPClientTests: XCTestCase {
    private var client: VaultUploadHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = BaseHTTPClient(
            session: session,
            tokenProvider: { "test-bearer" },
        )
        client = VaultUploadHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testUploadAssetSendsHEIC() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.authorization = req.value(forHTTPHeaderField: "Authorization")
            let body = #"{"path":"raw/captures/x.heic","size":12,"content_type":"image/heic","sha256":"deadbeef"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let resp = try await client.uploadAsset(
            data: Data(repeating: 0xAA, count: 12),
            contentType: "image/heic",
            relativePath: "raw/captures/x.heic",
            spaceID: nil,
        )

        XCTAssertEqual(resp.path, "raw/captures/x.heic")
        XCTAssertEqual(resp.contentType, "image/heic")
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/vault/files")
        XCTAssertEqual(captured.url?.query, "path=raw/captures/x.heic")
        XCTAssertEqual(captured.contentType, "image/heic")
        XCTAssertEqual(captured.authorization, "Bearer test-bearer")
    }

    func testUploadAssetSendsJPEG() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.url = req.url
            let body = #"{"path":"raw/captures/y.jpg","size":4,"content_type":"image/jpeg","sha256":"cafe"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let resp = try await client.uploadAsset(
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            contentType: "image/jpeg",
            relativePath: "raw/captures/y.jpg",
            spaceID: nil,
        )
        XCTAssertEqual(resp.path, "raw/captures/y.jpg")
        XCTAssertEqual(captured.contentType, "image/jpeg")
        XCTAssertEqual(captured.url?.query, "path=raw/captures/y.jpg")
    }

    /// HER-CaptureTab — `space_id` rides as a second URL query item.
    func testUploadAssetSendsSpaceID() async throws {
        let captured = CaptureBox()
        let space = UUID()
        MockURLProtocol.handler = { req in
            captured.url = req.url
            let body = #"{"path":"raw/captures/z.heic","size":4,"content_type":"image/heic","sha256":"ab"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }
        _ = try await client.uploadAsset(
            data: Data([0x01, 0x02, 0x03, 0x04]),
            contentType: "image/heic",
            relativePath: "raw/captures/z.heic",
            spaceID: space,
        )
        let query = captured.url?.query ?? ""
        XCTAssertTrue(query.contains("path=raw/captures/z.heic"))
        XCTAssertTrue(query.contains("space_id=\(space.uuidString)"))
    }

    /// Backlog E5.4 — a note save carries `If-Match`, and a 412 surfaces as a
    /// conflict the reader can tell apart from other failures.
    func testUploadNoteSendsIfMatchAndSurfaces412() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.ifMatch = req.value(forHTTPHeaderField: "If-Match")
            let body = #"{"error":{"message":"the file changed since you opened it"}}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 412, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }
        do {
            _ = try await client.uploadNote(
                data: Data("v2".utf8), contentType: "text/markdown",
                relativePath: "inbox/n.md", spaceID: nil, metadata: nil,
                ifMatch: NoteVersion.ifMatch("abc"),
            )
            XCTFail("expected a 412")
        } catch {
            XCTAssertTrue(NoteVersion.isConflict(error), "\(error)")
        }
        XCTAssertEqual(captured.ifMatch, "\"abc\"")
    }

    func testUploadNoteWithoutVersionSendsNoIfMatch() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.ifMatch = req.value(forHTTPHeaderField: "If-Match")
            let body = #"{"path":"inbox/n.md","size":2,"content_type":"text/markdown","sha256":"ab"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }
        _ = try await client.uploadNote(
            data: Data("v2".utf8), contentType: "text/markdown",
            relativePath: "inbox/n.md", spaceID: nil, metadata: nil,
        )
        XCTAssertNil(captured.ifMatch)
    }

    /// An edit is saved in place with `PUT /v1/vault/files/{path}`, at any
    /// depth, so a nested note is never refiled under its Space's folder.
    func testReplaceNotePutsAtTheNotesOwnPath() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
            captured.ifMatch = req.value(forHTTPHeaderField: "If-Match")
            captured.metadata = req.value(forHTTPHeaderField: "X-Vault-Metadata")
            let body = #"{"path":"lore/people/ada.md","size":2,"contentType":"text/markdown","sha256":"ab"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }
        let resp = try await client.replaceNote(
            data: Data("v2".utf8), contentType: "text/markdown",
            relativePath: "lore/people/ada.md",
            metadata: VaultNoteMetadataDTO(title: "Ada"),
            ifMatch: NoteVersion.ifMatch("abc"),
        )
        XCTAssertEqual(resp.path, "lore/people/ada.md")
        XCTAssertEqual(captured.method, "PUT")
        XCTAssertEqual(captured.url?.path, "/v1/vault/files/lore/people/ada.md")
        XCTAssertEqual(captured.url?.query, "processed=true&note=true")
        XCTAssertEqual(captured.ifMatch, "\"abc\"")
        XCTAssertTrue(captured.metadata?.contains("\"title\":\"Ada\"") ?? false, captured.metadata ?? "nil")
    }

    func testNoteVersionHashesLikeTheServer() {
        // sha256("abc"), the FIPS 180-2 test vector.
        XCTAssertEqual(
            NoteVersion.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        )
        XCTAssertNil(NoteVersion.ifMatch(nil))
        XCTAssertFalse(NoteVersion.isConflict(APIError.httpError(statusCode: 409, data: Data())))
    }
}

private final class CaptureBox: @unchecked Sendable {
    var metadata: String?
    var method: String?
    var url: URL?
    var contentType: String?
    var authorization: String?
    var ifMatch: String?
}
