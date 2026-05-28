// LuminaVaultClient/LuminaVaultClientTests/ReflectionRunnerTests.swift
//
// HER-194 — unit coverage for the Reflect tab's per-run state machine.
// Stubs `SkillsClientProtocol` + `VaultUploadClientProtocol` directly
// to keep tests off the network layer.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ReflectionRunnerTests: XCTestCase {

    // MARK: - State transitions

    func testRunSuccessTransitionsIdleToResult() async {
        let stub = StubSkillsClient(runResult: .success(Self.makeResponse(markdown: "# ok")))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .patterns, topic: "productivity")
        guard case .result(let response) = runner.state else {
            return XCTFail("expected .result, got \(runner.state)")
        }
        XCTAssertEqual(response.markdown, "# ok")
    }

    func testRunMapsRateLimitedToFriendlyMessage() async {
        let stub = StubSkillsClient(runResult: .failure(APIError.rateLimited(retryAfter: nil)))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .patterns, topic: nil)
        guard case .failed(let error) = runner.state, error == .rateLimited else {
            return XCTFail("expected .failed(.rateLimited), got \(runner.state)")
        }
        XCTAssertEqual(error.userMessage, "You've used your 3 reflections today. Resets at midnight.")
    }

    func testRunMapsArbitraryErrorToNetwork() async {
        let stub = StubSkillsClient(runResult: .failure(APIError.networkFailure(URLError(.timedOut))))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .patterns, topic: nil)
        guard case .failed(.network) = runner.state else {
            return XCTFail("expected .failed(.network), got \(runner.state)")
        }
    }

    func testBeliefsRequiresTopicAndShortCircuitsValidation() async {
        let stub = StubSkillsClient(runResult: .success(Self.makeResponse(markdown: "n/a")))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .beliefs, topic: "   ")
        guard case .failed(.validation) = runner.state else {
            return XCTFail("expected .failed(.validation), got \(runner.state)")
        }
        XCTAssertFalse(stub.runCalled, "skill should not dispatch when validation fails")
    }

    func testPatternsAcceptsEmptyTopic() async {
        let stub = StubSkillsClient(runResult: .success(Self.makeResponse(markdown: "# patterns")))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .patterns, topic: "")
        guard case .result = runner.state else {
            return XCTFail("expected .result, got \(runner.state)")
        }
        XCTAssertTrue(stub.runCalled)
        XCTAssertNil(stub.lastRequest?.input)
    }

    func testRunRequestHasSaveFalse() async {
        let stub = StubSkillsClient(runResult: .success(Self.makeResponse(markdown: "x")))
        let runner = ReflectionRunner(skillsClient: stub, vaultUploadClient: StubUploadClient())
        await runner.run(skill: .patterns, topic: "x")
        XCTAssertEqual(stub.lastRequest?.save, false)
    }

    // MARK: - Save

    func testSaveUploadsCachedMarkdownAndReachesSaved() async {
        let response = Self.makeResponse(markdown: "# saved body")
        let runner = ReflectionRunner(
            skillsClient: StubSkillsClient(runResult: .success(response)),
            vaultUploadClient: StubUploadClient(),
        )
        await runner.save(skill: .patterns, topic: "focus", response: response)
        guard case .saved(_, let savedPath) = runner.state else {
            return XCTFail("expected .saved, got \(runner.state)")
        }
        XCTAssertTrue(savedPath.hasPrefix("reflections/"))
        XCTAssertTrue(savedPath.hasSuffix("/patterns-focus.md"))
    }

    // MARK: - savePath

    func testSavePathUsesISODateAndSkillSlug() {
        let path = ReflectionRunner.savePath(skill: .contradictions, topic: "JavaScript Frameworks!")
        // path shape: reflections/yyyy-MM-dd/contradictions-javascript-frameworks.md
        let parts = path.split(separator: "/")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "reflections")
        XCTAssertTrue(parts[2].hasPrefix("contradictions-"))
        XCTAssertTrue(parts[2].hasSuffix(".md"))
    }

    func testSavePathFallsBackToUntitledOnNil() {
        let path = ReflectionRunner.savePath(skill: .patterns, topic: nil)
        XCTAssertTrue(path.contains("/patterns-untitled.md"))
    }

    // MARK: - slugify

    func testSlugifyLowercasesAndHyphenates() {
        XCTAssertEqual(ReflectionRunner.slugify("Remote Work"), "remote-work")
    }

    func testSlugifyCollapsesPunctuationRuns() {
        XCTAssertEqual(ReflectionRunner.slugify("hello!!  world??"), "hello-world")
    }

    func testSlugifyStripsLeadingTrailingDashes() {
        XCTAssertEqual(ReflectionRunner.slugify("  ---test---  "), "test")
    }

    func testSlugifyHandlesUnicode() {
        // café → cafe ; 北京 → bei-jing-ish (toLatin transliteration). Just
        // assert ASCII-only output and non-empty.
        let slug = ReflectionRunner.slugify("Café résumé")
        XCTAssertFalse(slug.isEmpty)
        XCTAssertTrue(slug.allSatisfy { $0.isASCII })
        XCTAssertFalse(slug.contains(" "))
    }

    func testSlugifyCapsAt40Chars() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(ReflectionRunner.slugify(long).count, 40)
    }

    func testSlugifyEmptyInputBecomesUntitled() {
        XCTAssertEqual(ReflectionRunner.slugify(""), "untitled")
        XCTAssertEqual(ReflectionRunner.slugify("   "), "untitled")
    }

    // MARK: - Fixtures

    private static func makeResponse(markdown: String) -> SkillRunResponse {
        SkillRunResponse(
            id: UUID(),
            skillName: "patterns",
            status: .success,
            markdown: markdown,
            savedPath: nil,
            modelUsed: "claude",
            mtokIn: nil,
            mtokOut: nil,
            startedAt: Date(),
            endedAt: Date(),
        )
    }
}

// MARK: - Stubs

private final class StubSkillsClient: SkillsClientProtocol, @unchecked Sendable {
    let runResult: Result<SkillRunResponse, Error>
    var runCalled = false
    var lastRequest: SkillRunRequest?

    init(runResult: Result<SkillRunResponse, Error>) {
        self.runResult = runResult
    }

    func list() async throws -> SkillListResponse {
        SkillListResponse(skills: [])
    }
    func patch(name: String, body: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO {
        throw APIError.networkFailure(URLError(.unsupportedURL))
    }
    func runs(name: String, limit: Int?) async throws -> SkillRunsResponse {
        SkillRunsResponse(runs: [], sparkline: [], nextCursor: nil)
    }
    func run(name: String, request: SkillRunRequest) async throws -> SkillRunResponse {
        runCalled = true
        lastRequest = request
        return try runResult.get()
    }
}

private final class StubUploadClient: VaultUploadClientProtocol, @unchecked Sendable {
    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?
    ) async throws -> VaultUploadResponse {
        VaultUploadResponse(
            path: relativePath,
            size: data.count,
            contentType: contentType,
            sha256: "stub",
        )
    }
}
