// LuminaVaultClient/LuminaVaultClient/API/Onboarding/OnboardingEndpoints.swift
//
// HER-93 / HER-100 — server-tracked onboarding state.
//   GET   /v1/onboarding  -> OnboardingStateDTO
//   PATCH /v1/onboarding  -> OnboardingStateDTO  (one-way latch per flag)

import Foundation
import LuminaVaultShared

enum OnboardingEndpoints {
    struct Get: Endpoint {
        typealias Response = OnboardingStateDTO
        var path: String { "/v1/onboarding" }
        var method: HTTPMethod { .get }
    }

    struct Patch: Endpoint {
        typealias Response = OnboardingStateDTO
        let request: OnboardingPatchRequest
        var path: String { "/v1/onboarding" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }
}
