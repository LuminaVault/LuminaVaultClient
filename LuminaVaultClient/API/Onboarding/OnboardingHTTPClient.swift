// LuminaVaultClient/LuminaVaultClient/API/Onboarding/OnboardingHTTPClient.swift
//
// HER-93 / HER-100 — BaseHTTPClient-backed onboarding state client.

import Foundation
import LuminaVaultShared

protocol OnboardingClientProtocol: Sendable {
    func get() async throws -> OnboardingStateDTO
    func patch(_ body: OnboardingPatchRequest) async throws -> OnboardingStateDTO
}

final class OnboardingHTTPClient: OnboardingClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> OnboardingStateDTO {
        try await client.execute(OnboardingEndpoints.Get())
    }

    func patch(_ body: OnboardingPatchRequest) async throws -> OnboardingStateDTO {
        try await client.execute(OnboardingEndpoints.Patch(request: body))
    }
}
