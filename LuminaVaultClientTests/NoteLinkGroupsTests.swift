// LuminaVaultClient/LuminaVaultClientTests/NoteLinkGroupsTests.swift
// Backlog E2.2 — grouping GET /v1/vault/links for the reader.

@testable import LuminaVaultClient
import Foundation
import XCTest

final class NoteLinkGroupsTests: XCTestCase {
    private func response(
        path: String = "notes/dentist.md",
        outgoing: [VaultOutgoingLink] = [],
        incoming: [VaultIncomingLink] = []
    ) -> VaultLinksResponse {
        VaultLinksResponse(vaultFileID: UUID(), path: path, outgoing: outgoing, incoming: incoming)
    }

    func testLinkedFromCountsRepeatsAndSortsByPath() {
        let groups = NoteLinkGroups(response(incoming: [
            VaultIncomingLink(sourcePath: "journal/2026-11-02.md", rawTarget: "dentist", targetSlug: "dentist"),
            VaultIncomingLink(sourcePath: "health/teeth.md", rawTarget: "dentist", targetSlug: "dentist"),
            VaultIncomingLink(sourcePath: "health/teeth.md", rawTarget: "Dentist", targetSlug: "dentist"),
        ]))
        XCTAssertEqual(groups.linkedFrom.map(\.path), ["health/teeth.md", "journal/2026-11-02.md"])
        XCTAssertEqual(groups.linkedFrom.map(\.count), [2, 1])
    }

    func testOutgoingSplitsWrittenAndUnwrittenNotes() {
        let groups = NoteLinkGroups(response(outgoing: [
            VaultOutgoingLink(rawTarget: "insurance", targetSlug: "insurance", targetPath: "admin/insurance.md"),
            VaultOutgoingLink(rawTarget: "Floss routine", targetSlug: "floss-routine", resolutionState: "missing", targetPath: nil),
            VaultOutgoingLink(rawTarget: "floss routine", targetSlug: "floss-routine", resolutionState: "missing", targetPath: nil),
        ]))
        XCTAssertEqual(groups.linksTo.map(\.path), ["admin/insurance.md"])
        XCTAssertEqual(groups.unresolved.count, 1)
        XCTAssertNil(groups.unresolved.first?.path)
        XCTAssertEqual(groups.unresolved.first?.label, "Floss routine")
        XCTAssertEqual(groups.unresolved.first?.count, 2)
    }

    func testDropsSelfLinksAndSourcelessBacklinks() {
        let groups = NoteLinkGroups(response(
            outgoing: [VaultOutgoingLink(rawTarget: "dentist", targetSlug: "dentist", targetPath: "notes/dentist.md")],
            incoming: [
                VaultIncomingLink(sourcePath: "notes/dentist.md", rawTarget: "dentist", targetSlug: "dentist"),
                VaultIncomingLink(sourcePath: nil, rawTarget: "dentist", targetSlug: "dentist"),
            ]
        ))
        XCTAssertTrue(groups.isEmpty)
    }

    func testDecodesServerShape() throws {
        let json = Data("""
        {"vaultFileID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","path":"notes/dentist.md",
         "outgoing":[{"sourceLine":4,"rawTarget":"insurance","targetSlug":"insurance","resolutionState":"resolved","targetPath":"admin/insurance.md"}],
         "incoming":[{"sourcePath":"health/teeth.md","sourceLine":2,"rawTarget":"dentist","targetSlug":"dentist","resolutionState":"resolved"}]}
        """.utf8)
        let decoded = try JSONDecoder.hvDefault.decode(VaultLinksResponse.self, from: json)
        XCTAssertEqual(decoded.outgoing.first?.targetPath, "admin/insurance.md")
        XCTAssertEqual(decoded.incoming.first?.sourcePath, "health/teeth.md")
    }
}
