// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/AssistantActionsHTTPClientTests.swift
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

final class AssistantActionsHTTPClientTests: XCTestCase {
    private var client: AssistantActionsHTTPClient!
    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = AssistantActionsHTTPClient(client: BaseHTTPClient(session: URLSession(configuration: config)))
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func respond(_ status: Int, _ json: String, _ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(json.utf8))
    }

    func testConfirmPostsToConfirmPath() async throws {
        MockURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/assistant/actions/\(id.uuidString.lowercased())/confirm")
            return respond(200, #"{"status":"alreadyResolved","message":"Done."}"#, request)
        }
        let result = try await client.confirm(id)
        XCTAssertEqual(result.status, .alreadyResolved)
        XCTAssertEqual(result.message, "Done.")
    }

    func testCancelPostsToCancelPathAndUnknownStatusDecodes() async throws {
        MockURLProtocol.handler = { [self] request in
            XCTAssertEqual(request.url?.path, "/v1/assistant/actions/\(id.uuidString.lowercased())/cancel")
            return respond(200, #"{"status":"somethingNew","message":"?"}"#, request)
        }
        let result = try await client.cancel(id)
        XCTAssertEqual(result.status, .unknown)
    }

    func test404SurfacesAsHTTPError() async {
        MockURLProtocol.handler = { [self] request in respond(404, #"{"error":{"message":"not found"}}"#, request) }
        do {
            _ = try await client.confirm(id)
            XCTFail("expected throw")
        } catch let APIError.httpError(code, _) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
