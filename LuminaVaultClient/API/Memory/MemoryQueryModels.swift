// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryModels.swift
// HER-213: DTOs sourced from LuminaVaultShared. Retroactive Equatable +
// Identifiable conformances live here because Shared keeps its wire-types
// free of SwiftUI-driven protocols.
import Foundation
@_exported import LuminaVaultShared

typealias QueryHitDTO = LuminaVaultShared.QueryHitDTO
typealias QueryResponse = LuminaVaultShared.QueryResponse

extension LuminaVaultShared.MemoryDTO: @retroactive Equatable, @retroactive Identifiable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.content == rhs.content
            && lhs.tags == rhs.tags
            && lhs.createdAt == rhs.createdAt
            && lhs.lat == rhs.lat
            && lhs.lng == rhs.lng
            && lhs.accuracyM == rhs.accuracyM
            && lhs.placeName == rhs.placeName
    }
}

extension LuminaVaultShared.QueryHitDTO: @retroactive Equatable, @retroactive Identifiable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.content == rhs.content
            && lhs.distance == rhs.distance
            && lhs.createdAt == rhs.createdAt
    }
}

extension LuminaVaultShared.QueryResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary == rhs.summary && lhs.hits == rhs.hits
    }
}
