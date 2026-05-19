// LuminaVaultClient/LuminaVaultClientTests/Persistence/SwiftDataStackTests.swift
import XCTest
import Foundation
import SwiftData
@testable import LuminaVaultClient

@MainActor
final class SwiftDataStackTests: XCTestCase {
    func testInMemoryContainerBuilds() throws {
        let container = try SwiftDataStack.makeInMemory()
        XCTAssertNotNil(container.mainContext)
    }

    func testCanPersistAndFetchLocalVaultFile() throws {
        let container = try SwiftDataStack.makeInMemory()
        let context = container.mainContext

        let tenant = UUID()
        let row = LocalVaultFile(
            id: UUID(),
            tenantID: tenant,
            path: "notes/today.md",
            contentType: "text/markdown",
            sizeBytes: 42,
            sha256: "deadbeef"
        )
        context.insert(row)
        try context.save()

        let descriptor = FetchDescriptor<LocalVaultFile>()
        let rows = try context.fetch(descriptor)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.path, "notes/today.md")
        XCTAssertEqual(rows.first?.tenantID, tenant)
    }

    func testCanPersistSyncOperationWithEnumBacking() throws {
        let container = try SwiftDataStack.makeInMemory()
        let context = container.mainContext

        let op = SyncOperation(
            tenantID: UUID(),
            type: .uploadFile,
            pathInVault: "a.md"
        )
        op.state = .inFlight
        context.insert(op)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.type, .uploadFile)
        XCTAssertEqual(fetched.first?.state, .inFlight)
    }

    func testCanPersistSyncLogEntry() throws {
        let container = try SwiftDataStack.makeInMemory()
        let context = container.mainContext

        let entry = SyncLogEntry(
            tenantID: UUID(),
            operationID: UUID(),
            result: "success",
            message: "drained 3 ops"
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncLogEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.result, "success")
    }
}
