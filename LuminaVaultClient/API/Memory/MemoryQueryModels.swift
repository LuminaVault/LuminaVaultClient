// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryModels.swift
//
// HER-157 — local Codable mirrors of LuminaVaultShared's QueryResponse +
// QueryHitDTO (server v0.3.0+). HER-213 will swap these for
// `import LuminaVaultShared` once the SPM dep is wired; field shapes match
// 1:1 with `QueryController.swift:25` / `APIDTOs.swift:396-413`.

import Foundation

struct QueryHitDTO: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let content: String
    let distance: Float
    let createdAt: Date?
}

struct QueryResponse: Codable, Sendable, Equatable {
    let summary: String
    let hits: [QueryHitDTO]
}
