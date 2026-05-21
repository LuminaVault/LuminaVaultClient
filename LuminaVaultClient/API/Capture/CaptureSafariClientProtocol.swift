// LuminaVaultClient/LuminaVaultClient/API/Capture/CaptureSafariClientProtocol.swift
//
// HER-257 — protocol seam so the drainer + share-extension (HER-258)
// can stub the network layer in tests.

import Foundation

protocol CaptureSafariClientProtocol: Sendable {
    /// POST /v1/capture/safari — enqueues async URL enrichment (OG /
    /// oEmbed / X scrape) and returns the vault file id once the row
    /// lands on disk. `enrichmentStatus` rides separately and reflects
    /// the background job.
    func capture(_ request: CaptureSafariRequest) async throws -> CaptureSafariResponse
}
