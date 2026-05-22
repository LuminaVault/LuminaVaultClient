// LuminaVaultClient/LuminaVaultClient/API/Billing/BillingHTTPClient.swift
//
// HER-185 — BaseHTTPClient-backed implementation of BillingClientProtocol.

import Foundation
import LuminaVaultShared

final class BillingHTTPClient: BillingClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func fetchMeBilling() async throws -> MeBillingResponse {
        try await client.execute(BillingEndpoints.GetMeBilling())
    }
}
