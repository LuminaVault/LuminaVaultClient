// LuminaVaultClient/LuminaVaultClientTests/VaultNoteMetadataDecodingTests.swift
//
// A captured link's enrichment status has to survive the wire.
//
// This is really a guard on the LuminaVaultShared pin. `enrichmentStatus`
// arrived in 5.13.0; if the pin is ever rolled back, this file stops compiling
// rather than the feed quietly losing the ability to tell a placeholder link
// from a finished one — which is exactly the failure it was added to end, and
// is invisible at runtime.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class VaultNoteMetadataDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> VaultFileDTO {
        try JSONDecoder.hvDefault.decode(VaultFileDTO.self, from: Data(json.utf8))
    }

    func testEnrichmentStatusIsCarriedOnTheMetadata() throws {
        let file = try decode("""
        {
          "id": "8E1D6B4E-6E8E-4C4C-9C1B-3F0F9F4B7A11",
          "path": "inbox/2026-09-13-143005-example-com-ab12cd34.md",
          "contentType": "text/markdown",
          "sizeBytes": 118,
          "sha256": "",
          "metadata": { "enrichmentStatus": "pending" }
        }
        """)

        XCTAssertEqual(file.metadata?.enrichmentStatus, "pending")
    }

    func testAFinishedLinkSaysSo() throws {
        let file = try decode("""
        {
          "id": "8E1D6B4E-6E8E-4C4C-9C1B-3F0F9F4B7A11",
          "path": "inbox/2026-09-13-143005-example-com-ab12cd34.md",
          "contentType": "text/markdown",
          "sizeBytes": 2400,
          "sha256": "",
          "metadata": { "title": "Building a second brain", "enrichmentStatus": "done" }
        }
        """)

        XCTAssertEqual(file.metadata?.enrichmentStatus, "done")
        XCTAssertEqual(file.metadata?.title, "Building a second brain")
    }

    func testAnOrdinaryNoteHasNoEnrichmentStatus() throws {
        // Only captured links carry it. A note that reported "pending" would
        // sit in the feed claiming to be fetching a page that does not exist.
        let file = try decode("""
        {
          "id": "8E1D6B4E-6E8E-4C4C-9C1B-3F0F9F4B7A11",
          "path": "inbox/a-note.md",
          "contentType": "text/markdown",
          "sizeBytes": 42,
          "sha256": "",
          "metadata": { "title": "A note", "isTodo": false }
        }
        """)

        XCTAssertNil(file.metadata?.enrichmentStatus)
    }

    func testMetadataMayBeAbsentEntirely() throws {
        let file = try decode("""
        {
          "id": "8E1D6B4E-6E8E-4C4C-9C1B-3F0F9F4B7A11",
          "path": "inbox/photo.png",
          "contentType": "image/png",
          "sizeBytes": 90210,
          "sha256": ""
        }
        """)

        XCTAssertNil(file.metadata)
    }
}
