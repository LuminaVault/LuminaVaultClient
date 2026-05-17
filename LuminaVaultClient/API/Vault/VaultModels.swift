// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultModels.swift
// HER-35: Vault init handshake DTOs sourced from LuminaVaultShared.
// Retroactive Equatable lives here so the rest of Shared stays free of
// SwiftUI-driven protocols.
import Foundation
@_exported import LuminaVaultShared

typealias VaultStatusResponse = LuminaVaultShared.VaultStatusResponse
typealias VaultCreateRequest = LuminaVaultShared.VaultCreateRequest

extension LuminaVaultShared.VaultStatusResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.initialized == rhs.initialized
            && lhs.createdAt == rhs.createdAt
            && lhs.defaultSpaceSlugs == rhs.defaultSpaceSlugs
    }
}
