// LuminaVaultClient/LuminaVaultClient/API/Spaces/SpacesModels.swift
// HER-35: Spaces DTOs sourced from LuminaVaultShared. Adds the retroactive
// Identifiable + Equatable conformances SwiftUI's diff engine needs to keep
// list animations stable.
import Foundation
@_exported import LuminaVaultShared

typealias SpaceDTO = LuminaVaultShared.SpaceDTO
typealias SpaceListResponse = LuminaVaultShared.SpaceListResponse
typealias CreateSpaceRequest = LuminaVaultShared.CreateSpaceRequest
typealias UpdateSpaceRequest = LuminaVaultShared.UpdateSpaceRequest

extension LuminaVaultShared.SpaceDTO: @retroactive Equatable, @retroactive Identifiable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.slug == rhs.slug
            && lhs.description == rhs.description
            && lhs.color == rhs.color
            && lhs.icon == rhs.icon
            && lhs.category == rhs.category
            && lhs.noteCount == rhs.noteCount
            && lhs.lastCompiledAt == rhs.lastCompiledAt
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
    }
}

extension LuminaVaultShared.SpaceListResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spaces == rhs.spaces
    }
}
