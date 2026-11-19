// LuminaVaultClient/LuminaVaultClientTests/SlashCommandCatalogTests.swift
//
// Chat slash commands: the composer's suggestion rules and the
// `POST /v1/skills/slash` wire shape.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

enum SlashSkillFixture {
    static func skill(_ name: String, enabled: Bool) -> LuminaVaultShared.SkillDTO {
        LuminaVaultShared.SkillDTO(
            id: "builtin:\(name)",
            source: .builtin,
            name: name,
            title: name,
            descriptionText: "About \(name)",
            capability: .medium,
            schedule: nil,
            scheduleOverride: nil,
            enabled: enabled,
            lastRunAt: nil,
            lastStatus: nil,
            lastError: nil,
            dailyRunCount: 0,
            dailyRunCap: 10,
            apnsCategory: nil,
            bodyExcerpt: ""
        )
    }
}

final class SlashCommandCatalogTests: XCTestCase {
    func testIsCommand() {
        XCTAssertTrue(SlashCommandCatalog.isCommand("/kb-compile"))
        XCTAssertTrue(SlashCommandCatalog.isCommand("/patterns sleep"))
        XCTAssertFalse(SlashCommandCatalog.isCommand("/"))
        XCTAssertFalse(SlashCommandCatalog.isCommand("/ hello"))
        XCTAssertFalse(SlashCommandCatalog.isCommand("//comment"))
        XCTAssertFalse(SlashCommandCatalog.isCommand("what is a/b"))
    }

    func testMatchesOnlyABareCommandWord() {
        let catalog = SlashCommandCatalog.builtIns
        XCTAssertEqual(SlashCommandCatalog.matches(for: "/", in: catalog).count, 4)
        XCTAssertEqual(SlashCommandCatalog.matches(for: "/C", in: catalog).map(\.name), ["contradict"])
        XCTAssertTrue(SlashCommandCatalog.matches(for: "/beliefs x", in: catalog).isEmpty)
        XCTAssertTrue(SlashCommandCatalog.matches(for: "hello", in: catalog).isEmpty)
        XCTAssertEqual(SlashCommandCatalog.builtIns[1].insertion, "/patterns ")
    }

    func testSkillSuggestionsSkipDisabledAliasedAndHermesSkills() {
        let names = SlashCommandCatalog.suggestions(from: [
            SlashSkillFixture.skill("daily-brief", enabled: true),
            SlashSkillFixture.skill("weekly-memo", enabled: false),
            SlashSkillFixture.skill("belief-evolution", enabled: true),
            SlashSkillFixture.skill("hermes-research", enabled: true),
        ]).map(\.name)
        XCTAssertEqual(names, ["daily-brief"])
    }
}

final class SkillsSlashHTTPClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRunSlashPostsTheCommandAsTyped() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = SkillsHTTPClient(client: BaseHTTPClient(
            session: URLSession(configuration: config),
            tokenProvider: { "t" }
        ))
        let captured = SlashCapture()
        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.path = req.url?.path
            captured.body = req.httpBody ?? req.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 {
                        break
                    }
                    data.append(buffer, count: n)
                }
                return data
            }
            let body = #"{"id":"6f1c2c1e-1b7a-4bde-9d55-0f3d3f2b8a11","skillName":"kb-compile","status":"success","markdown":"Compiled 3 notes","startedAt":"2026-11-18T10:00:00Z","endedAt":"2026-11-18T10:00:01Z"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        let response = try await client.runSlash(command: "/kb-compile")
        XCTAssertEqual(response.markdown, "Compiled 3 notes")
        XCTAssertEqual(response.skillName, "kb-compile")
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.path, "/v1/skills/slash")
        let json = try XCTUnwrap(captured.body
            .flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(json, ["command": "/kb-compile"])
    }
}

private final class SlashCapture: @unchecked Sendable {
    // Written once by MockURLProtocol's handler before the request returns;
    // read after the awaited call, so there is no concurrent access.
    var method: String?
    var path: String?
    var body: Data?
}
