// LuminaVaultClient/LuminaVaultClientTests/NotionImportTests.swift
//
// Backlog E7.4: the Notion import report, its endpoint and the two-step
// screen logic, against the wire contract fixed in the spec of 2026-11-18.

import Foundation
import XCTest
@testable import LuminaVaultClient

// MARK: - Report decoding

final class NotionImportReportDecodingTests: XCTestCase {
    /// The sample from the spec's "Wire contract" section, as an import
    /// (not a dry run) would return it.
    private static let contractSample = #"""
    {
      "dryRun": false,
      "spaceId": "7d0c7a0e-5f0b-4c0e-9a51-0d6a2f3b1c11",
      "spaceSlug": "notion",
      "pages": 120, "databases": 3, "rows": 85, "attachments": 40,
      "written": 230, "skipped": 12, "failed": 3,
      "links": {
        "resolved": 410, "external": 52, "unresolved": 6,
        "unresolvedList": [{ "page": "notion/roadmap.md", "target": "Old page 1a2b.md" }]
      },
      "columns": [{ "database": "Tasks", "name": "Status", "type": "select" }],
      "views": [{ "id": "0b9f6f0a-1111-4222-8333-444455556666", "name": "Tasks", "folder": "notion/tasks" }],
      "collisions": [{ "from": "Untitled 9f.md", "to": "notion/untitled-2.md" }],
      "files": [
        { "entry": "Roadmap 1a2b.md", "savedPath": "notion/roadmap.md", "kind": "page", "status": "imported" },
        { "entry": "Video.mov", "kind": "attachment", "status": "tooLarge" }
      ],
      "warnings": ["Tasks: column Due had date ranges; kept the start date"]
    }
    """#

    func testDecodesTheContractSample() throws {
        let report = try JSONDecoder.hvDefault.decode(
            VaultNotionImportReport.self, from: Data(Self.contractSample.utf8)
        )

        XCTAssertFalse(report.dryRun)
        XCTAssertEqual(report.spaceID, "7d0c7a0e-5f0b-4c0e-9a51-0d6a2f3b1c11")
        XCTAssertEqual(report.spaceSlug, "notion")
        XCTAssertEqual([report.pages, report.databases, report.rows, report.attachments], [120, 3, 85, 40])
        XCTAssertEqual([report.written, report.skipped, report.failed], [230, 12, 3])
        XCTAssertEqual([report.links.resolved, report.links.external, report.links.unresolved], [410, 52, 6])
        XCTAssertEqual(
            report.links.unresolvedList,
            [.init(page: "notion/roadmap.md", target: "Old page 1a2b.md")]
        )
        XCTAssertEqual(report.columns, [.init(database: "Tasks", name: "Status", type: "select")])
        XCTAssertEqual(
            report.views,
            [.init(id: "0b9f6f0a-1111-4222-8333-444455556666", name: "Tasks", folder: "notion/tasks")]
        )
        XCTAssertEqual(report.collisions, [.init(from: "Untitled 9f.md", to: "notion/untitled-2.md")])
        XCTAssertEqual(report.files.count, 2)
        XCTAssertEqual(report.files[0].savedPath, "notion/roadmap.md")
        XCTAssertEqual(report.files[0].kind, "page")
        XCTAssertNil(report.files[1].savedPath)
        XCTAssertEqual(report.files[1].status, "tooLarge")
        XCTAssertEqual(report.warnings, ["Tasks: column Due had date ranges; kept the start date"])
    }

    /// A dry run before the Space exists has no `spaceId` and no view ids, and
    /// with properties off the server sends empty lists, or none.
    func testDecodesADryRunWithAbsentFields() throws {
        let json = #"""
        {
          "dryRun": true,
          "spaceSlug": "notion",
          "pages": 2,
          "links": { "resolved": 1 },
          "views": [{ "name": "Tasks" }],
          "files": [{ "entry": "A.md", "status": "planned" }, { "kind": "other" }]
        }
        """#
        let report = try JSONDecoder.hvDefault.decode(VaultNotionImportReport.self, from: Data(json.utf8))

        XCTAssertTrue(report.dryRun)
        XCTAssertNil(report.spaceID)
        XCTAssertEqual(report.pages, 2)
        XCTAssertEqual(report.databases, 0)
        XCTAssertEqual(report.written, 0)
        XCTAssertEqual(report.links.resolved, 1)
        XCTAssertEqual(report.links.unresolved, 0)
        XCTAssertTrue(report.links.unresolvedList.isEmpty)
        XCTAssertNil(report.views.first?.id)
        XCTAssertEqual(report.views.first?.name, "Tasks")
        XCTAssertTrue(report.columns.isEmpty)
        XCTAssertTrue(report.warnings.isEmpty)
        XCTAssertEqual(report.files.map(\.status), ["planned", nil], "one odd entry must not fail the report")
    }
}

// MARK: - Endpoint

final class NotionImportEndpointTests: XCTestCase {
    private var client: VaultImportHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let base = BaseHTTPClient(session: URLSession(configuration: config), tokenProvider: { "test-bearer" })
        client = VaultImportHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testPostsTheRawZipWithTheContractQuery() async throws {
        let captured = RequestBox()
        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.authorization = req.value(forHTTPHeaderField: "Authorization")
            captured.body = Self.body(of: req)
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"dryRun":true,"spaceSlug":"notion","pages":4}"#.utf8)
            )
        }
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotionImportEndpointTests-\(UUID().uuidString).zip")
        try zip.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let report = try await client.importNotion(
            zipFile: file, space: "My Notion", dryRun: true, onConflict: "skip", onUploadProgress: nil
        )

        XCTAssertEqual(report.pages, 4)
        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/vault/import/notion")
        XCTAssertEqual(captured.url?.query, "space=My%20Notion&dryRun=true&onConflict=skip")
        XCTAssertEqual(captured.contentType, "application/zip")
        XCTAssertEqual(captured.authorization, "Bearer test-bearer")
        XCTAssertEqual(captured.body, zip, "the body is the ZIP itself, not multipart")
    }

    /// The server answers only after the whole import, so both steps carry a
    /// 15 minute idle timeout in place of the default 60 s.
    func testTheRequestHasTheLongTimeoutAndTheZipContentType() async throws {
        for dryRun in [true, false] {
            let request = try await client.notionImportRequest(space: "Notion", dryRun: dryRun, onConflict: "skip")

            XCTAssertEqual(request.timeoutInterval, 900)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/zip")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-bearer")
            XCTAssertEqual(request.url?.query, "space=Notion&dryRun=\(dryRun)&onConflict=skip")
            XCTAssertNil(request.httpBody, "the ZIP is streamed from disk, not held in the request")
        }
    }

    func testQueryCarriesTheRealImportAndEscapesTheSpaceName() {
        XCTAssertEqual(
            VaultImportHTTPClient.notionImportPath(space: "Notion", dryRun: false, onConflict: "skip"),
            "/v1/vault/import/notion?space=Notion&dryRun=false&onConflict=skip"
        )
        XCTAssertEqual(
            VaultImportHTTPClient.notionImportPath(space: "C++ & more", dryRun: true, onConflict: "overwrite"),
            "/v1/vault/import/notion?space=C%2B%2B%20%26%20more&dryRun=true&onConflict=overwrite"
        )
    }

    func testAnErrorStatusCarriesTheServersMessage() async {
        MockURLProtocol.handler = { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":{"message":"The export has more than 20,000 entries."}}"#.utf8)
            )
        }
        do {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("NotionImportEndpointTests-\(UUID().uuidString).zip")
            try Data([1]).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            _ = try await client.importNotion(
                zipFile: file, space: "Notion", dryRun: true, onConflict: "skip", onUploadProgress: nil
            )
            XCTFail("expected a 400")
        } catch {
            XCTAssertEqual((error as? APIError)?.httpStatusCode, 400)
            XCTAssertEqual(NotionImportViewModel.message(for: error), "The export has more than 20,000 entries.")
        }
    }

    /// URLSession hands a protocol stub the body as a stream, never `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Written once from the stub's handler, read after the request returns; the
/// request itself is the ordering, so no lock is needed.
private final class RequestBox: @unchecked Sendable {
    var method: String?
    var url: URL?
    var contentType: String?
    var authorization: String?
    var body: Data?
}

// MARK: - View model

@MainActor
final class NotionImportViewModelTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotionImportViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func export(bytes: Int, name: String = "Export-1a2b.zip") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 0x50, count: bytes).write(to: url)
        return url
    }

    func testDryRunThenImport() async throws {
        let client = FakeNotionClient()
        let viewModel = NotionImportViewModel(client: client)
        XCTAssertEqual(viewModel.spaceName, "Notion", "the Space name is prefilled")

        try await viewModel.pick(export(bytes: 64))
        XCTAssertEqual(viewModel.phase, .picked)
        XCTAssertEqual(viewModel.fileName, "Export-1a2b.zip")
        XCTAssertEqual(viewModel.fileBytes, 64)
        XCTAssertTrue(viewModel.canCheck)
        XCTAssertFalse(viewModel.canImport, "no import before a dry run")

        await viewModel.runImport()
        var calls = await client.calls
        XCTAssertTrue(calls.isEmpty, "Import does nothing until the export was checked")

        await viewModel.check()
        XCTAssertEqual(viewModel.phase, .checked)
        XCTAssertEqual(viewModel.report?.dryRun, true)
        XCTAssertEqual(viewModel.report?.pages, 7)
        XCTAssertTrue(viewModel.canImport)

        await viewModel.runImport()
        XCTAssertEqual(viewModel.phase, .done)
        XCTAssertEqual(viewModel.report?.dryRun, false)
        XCTAssertEqual(viewModel.report?.written, 7)
        XCTAssertNil(viewModel.errorMessage)

        calls = await client.calls
        XCTAssertEqual(calls.map(\.dryRun), [true, false])
        XCTAssertEqual(calls.map(\.space), ["Notion", "Notion"])
        XCTAssertEqual(calls.map(\.onConflict), ["skip", "skip"])
        XCTAssertEqual(calls.map(\.bytes), [64, 64], "both steps send the whole ZIP")
        XCTAssertNil(viewModel.uploadProgress, "no progress bar once the answer is in")
        let copy = try XCTUnwrap(calls.first?.file)
        XCTAssertFalse(copy.path.hasPrefix(folder.path), "the upload reads our own copy, not the picked file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "the temp copy is deleted after the import")
    }

    func testTheTempCopyGoesAwayWithTheViewModel() async throws {
        let client = FakeNotionClient()
        var viewModel: NotionImportViewModel? = NotionImportViewModel(client: client)
        try await viewModel?.pick(export(bytes: 8))
        await viewModel?.check()
        let firstCall = await client.calls.first
        let copy = try XCTUnwrap(firstCall?.file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "kept between the dry run and the import")

        viewModel = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testRenamingTheSpaceDropsTheDryRun() async throws {
        let client = FakeNotionClient()
        let viewModel = NotionImportViewModel(client: client)
        try await viewModel.pick(export(bytes: 8))
        await viewModel.check()
        XCTAssertTrue(viewModel.canImport)

        viewModel.spaceName = "  Work wiki "
        XCTAssertEqual(viewModel.phase, .picked)
        XCTAssertNil(viewModel.report)
        XCTAssertFalse(viewModel.canImport)

        await viewModel.check()
        let spaces = await client.calls.map(\.space)
        XCTAssertEqual(spaces, ["Notion", "Work wiki"], "the name is sent trimmed")

        viewModel.spaceName = "   "
        XCTAssertFalse(viewModel.canCheck, "a blank name can't be checked")
    }

    func testTooBigFileIsRefusedWithoutACall() async throws {
        let client = FakeNotionClient()
        let viewModel = NotionImportViewModel(client: client, maxBytes: 16)

        try await viewModel.pick(export(bytes: 17))

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.errorMessage, NotionImportViewModel.tooBigMessage)
        XCTAssertFalse(viewModel.canCheck)
        await viewModel.check()
        await viewModel.runImport()
        let calls = await client.calls
        XCTAssertTrue(calls.isEmpty)

        try await viewModel.pick(export(bytes: 16, name: "small.zip"))
        XCTAssertEqual(viewModel.phase, .picked, "a file at the limit is the server's call")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTheLimitIs200MB() {
        XCTAssertEqual(NotionImportViewModel.defaultMaxBytes, 209_715_200)
    }

    func testAServerErrorShowsItsMessageAndKeepsTheFile() async throws {
        let client = FakeNotionClient()
        await client.fail(with: APIError.httpError(
            statusCode: 400,
            data: Data(#"{"error":{"message":"That file is not a ZIP."}}"#.utf8)
        ))
        let viewModel = NotionImportViewModel(client: client)
        try await viewModel.pick(export(bytes: 8))

        await viewModel.check()

        XCTAssertEqual(viewModel.phase, .picked)
        XCTAssertEqual(viewModel.errorMessage, "That file is not a ZIP.")
        XCTAssertNil(viewModel.report)

        await client.fail(with: nil)
        await viewModel.check()
        XCTAssertEqual(viewModel.phase, .checked, "the same file can be checked again")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAFailedImportKeepsTheDryRunSoItCanBeRetried() async throws {
        let client = FakeNotionClient()
        let viewModel = NotionImportViewModel(client: client)
        try await viewModel.pick(export(bytes: 8))
        await viewModel.check()
        await client.fail(with: APIError.httpError(statusCode: 507, data: Data()))

        await viewModel.runImport()

        XCTAssertEqual(viewModel.phase, .checked)
        XCTAssertEqual(viewModel.errorMessage, "The server is out of storage space. Try again later.")
        XCTAssertTrue(viewModel.canImport)
    }

    func testACancelledRequestIsNotShownAsAFailure() async throws {
        let client = FakeNotionClient()
        await client.fail(with: CancellationError())
        let viewModel = NotionImportViewModel(client: client)
        try await viewModel.pick(export(bytes: 8))

        await viewModel.check()

        XCTAssertEqual(viewModel.phase, .picked)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorMessageMapping() {
        func http(_ status: Int, _ body: String = "") -> APIError {
            .httpError(statusCode: status, data: Data(body.utf8))
        }
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(400, #"{"error":{"message":"The ZIP is empty."}}"#)),
            "The ZIP is empty."
        )
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(413, #"{"error":{"message":"Over 200 MB."}}"#)),
            "Over 200 MB."
        )
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(507, #"{"error":{"message":"Disk is nearly full."}}"#)),
            "Disk is nearly full."
        )
        // No usable body: a proxy answered, or the envelope was empty.
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(400)),
            "That file isn't a Notion export the server can read."
        )
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(413, "<html>Request Entity Too Large</html>")),
            NotionImportViewModel.tooBigMessage
        )
        XCTAssertEqual(
            NotionImportViewModel.message(for: http(507)),
            "The server is out of storage space. Try again later."
        )
        XCTAssertEqual(NotionImportViewModel.message(for: http(500)), "Server error (500).")
        XCTAssertEqual(
            NotionImportViewModel.message(for: APIError.unauthorized),
            "Session expired. Please sign in again."
        )
    }
}

private actor FakeNotionClient: VaultImportClientProtocol {
    struct Call: Sendable {
        let space: String
        let dryRun: Bool
        let onConflict: String
        let file: URL
        let bytes: Int
    }

    private(set) var calls: [Call] = []
    private var failure: (any Error)?

    func fail(with error: (any Error)?) {
        failure = error
    }

    func bulk(space _: String, files _: [VaultBulkFile], onConflict _: String?) async throws -> VaultBulkResponse {
        throw URLError(.unsupportedURL)
    }

    func importNotion(
        zipFile: URL,
        space: String,
        dryRun: Bool,
        onConflict: String,
        onUploadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> VaultNotionImportReport {
        if let failure {
            throw failure
        }
        let bytes = (try? zipFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        calls.append(Call(space: space, dryRun: dryRun, onConflict: onConflict, file: zipFile, bytes: bytes))
        onUploadProgress?(0.5)
        onUploadProgress?(1)
        return VaultNotionImportReport(
            dryRun: dryRun,
            spaceID: dryRun ? nil : UUID().uuidString,
            spaceSlug: "notion",
            pages: 7,
            written: dryRun ? 0 : 7
        )
    }
}
