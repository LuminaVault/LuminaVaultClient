// LuminaVaultClient/LuminaVaultClient/API/Billing/BillingUsageDTOs.swift
//
// Local mirror of the v0.47 LuminaVaultShared usage DTOs. The Xcode project
// consumes LuminaVaultShared from the remote tagged package; keep this file
// until the shared package tag containing MeUsageResponse is adopted.

import Foundation
import LuminaVaultShared

struct UsageDailyPointDTO: Codable, Sendable, Equatable {
    let day: Date
    let tokensIn: Int64
    let tokensOut: Int64
    let ttsCharacters: Int64
    let compileRuns: Int64
    let compileFiles: Int64
}

struct MeUsageResponse: Codable, Sendable, Equatable {
    let tier: UserTier
    let periodStart: Date
    let periodEnd: Date
    let generatedAt: Date
    let storageBytes: Int64
    let tokensIn: Int64
    let tokensOut: Int64
    let tokensTotal: Int64
    let ttsCharacters: Int64
    let compileRuns: Int64
    let compileFiles: Int64
    let daily: [UsageDailyPointDTO]
}
