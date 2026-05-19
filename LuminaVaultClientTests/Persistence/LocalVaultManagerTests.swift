// LuminaVaultClient/LuminaVaultClientTests/Persistence/LocalVaultManagerTests.swift
import XCTest
import Foundation
@testable import LuminaVaultClient

final class LocalVaultManagerTests: XCTestCase {
    private var tempRoot: URL!
    private var sut: LocalVaultManager!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lv-test-\(UUID().uuidString)", isDirectory: true)
        sut = LocalVaultManager(baseURL: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        sut = nil
        super.tearDown()
    }

    // MARK: - ensureVaultExists

    func testEnsureVaultExistsCreatesRawAndLuminaDirs() async throws {
        let tenant = UUID()
        try await sut.ensureVaultExists(for: tenant)

        let root = await sut.vaultRootURL(for: tenant)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("raw").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".lumina/queue").path))
    }

    func testEnsureVaultExistsIsIdempotent() async throws {
        let tenant = UUID()
        try await sut.ensureVaultExists(for: tenant)
        try await sut.ensureVaultExists(for: tenant)  // second call must not throw
    }

    // MARK: - writeFile / readFile

    func testWriteThenReadRoundTrip() async throws {
        let tenant = UUID()
        let data = Data("hello vault".utf8)
        try await sut.writeFile(data, relativePath: "notes/hello.md", tenantID: tenant)

        let read = try await sut.readFile(relativePath: "notes/hello.md", tenantID: tenant)
        XCTAssertEqual(read, data)
    }

    func testWriteOverwritesExistingFile() async throws {
        let tenant = UUID()
        try await sut.writeFile(Data("v1".utf8), relativePath: "a.md", tenantID: tenant)
        try await sut.writeFile(Data("v2".utf8), relativePath: "a.md", tenantID: tenant)

        let read = try await sut.readFile(relativePath: "a.md", tenantID: tenant)
        XCTAssertEqual(read, Data("v2".utf8))
    }

    func testReadMissingFileThrows() async {
        let tenant = UUID()
        do {
            _ = try await sut.readFile(relativePath: "missing.md", tenantID: tenant)
            XCTFail("expected fileMissing")
        } catch LocalVaultManager.LocalVaultError.fileMissing {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - deleteFile

    func testDeleteRemovesFile() async throws {
        let tenant = UUID()
        try await sut.writeFile(Data("x".utf8), relativePath: "doomed.md", tenantID: tenant)
        try await sut.deleteFile(relativePath: "doomed.md", tenantID: tenant)

        let url = try await sut.rawFileURL(for: tenant, relativePath: "doomed.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteAbsentFileIsNoOp() async throws {
        let tenant = UUID()
        try await sut.ensureVaultExists(for: tenant)
        // Must not throw — deletion of a missing file is treated as success.
        try await sut.deleteFile(relativePath: "ghost.md", tenantID: tenant)
    }

    // MARK: - moveFile

    func testMoveRenamesFile() async throws {
        let tenant = UUID()
        try await sut.writeFile(Data("payload".utf8), relativePath: "old.md", tenantID: tenant)
        try await sut.moveFile(from: "old.md", to: "new.md", tenantID: tenant)

        let oldURL = try await sut.rawFileURL(for: tenant, relativePath: "old.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

        let read = try await sut.readFile(relativePath: "new.md", tenantID: tenant)
        XCTAssertEqual(read, Data("payload".utf8))
    }

    func testMoveRefusesToOverwriteExisting() async throws {
        let tenant = UUID()
        try await sut.writeFile(Data("a".utf8), relativePath: "a.md", tenantID: tenant)
        try await sut.writeFile(Data("b".utf8), relativePath: "b.md", tenantID: tenant)

        do {
            try await sut.moveFile(from: "a.md", to: "b.md", tenantID: tenant)
            XCTFail("expected writeFailed")
        } catch LocalVaultManager.LocalVaultError.writeFailed {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }

        // Both files still exist.
        XCTAssertEqual(try await sut.readFile(relativePath: "a.md", tenantID: tenant), Data("a".utf8))
        XCTAssertEqual(try await sut.readFile(relativePath: "b.md", tenantID: tenant), Data("b".utf8))
    }

    // MARK: - Tenant isolation

    func testTenantsAreIsolated() async throws {
        let alice = UUID()
        let bob = UUID()
        try await sut.writeFile(Data("alice".utf8), relativePath: "shared.md", tenantID: alice)
        try await sut.writeFile(Data("bob".utf8), relativePath: "shared.md", tenantID: bob)

        XCTAssertEqual(try await sut.readFile(relativePath: "shared.md", tenantID: alice), Data("alice".utf8))
        XCTAssertEqual(try await sut.readFile(relativePath: "shared.md", tenantID: bob), Data("bob".utf8))
    }

    // MARK: - Path validation

    func testRejectsPathEscape() async {
        let tenant = UUID()
        do {
            _ = try await sut.rawFileURL(for: tenant, relativePath: "../outside.md")
            XCTFail("expected pathEscapesVault")
        } catch LocalVaultManager.LocalVaultError.pathEscapesVault {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRejectsAbsolutePath() async {
        let tenant = UUID()
        do {
            _ = try await sut.rawFileURL(for: tenant, relativePath: "/etc/passwd")
            XCTFail("expected pathEscapesVault")
        } catch LocalVaultManager.LocalVaultError.pathEscapesVault {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Queued body persistence

    func testWriteQueuedBodyAndReadBack() async throws {
        let tenant = UUID()
        let opID = UUID()
        let body = Data(repeating: 0x42, count: 64)
        let relativePath = try await sut.writeQueuedBody(body, operationID: opID, tenantID: tenant)

        XCTAssertTrue(relativePath.hasPrefix(".lumina/queue/"))
        let read = try await sut.readQueuedBody(relativePath: relativePath, tenantID: tenant)
        XCTAssertEqual(read, body)

        await sut.deleteQueuedBody(relativePath: relativePath, tenantID: tenant)
        do {
            _ = try await sut.readQueuedBody(relativePath: relativePath, tenantID: tenant)
            XCTFail("expected fileMissing")
        } catch LocalVaultManager.LocalVaultError.fileMissing {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
