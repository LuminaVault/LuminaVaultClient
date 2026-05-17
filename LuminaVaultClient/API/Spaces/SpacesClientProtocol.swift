// LuminaVaultClient/LuminaVaultClient/API/Spaces/SpacesClientProtocol.swift
// HER-35: Spaces CRUD facade. ViewModel + tests depend on the protocol so
// the HTTPClient can be swapped for a Mock without touching call sites.
import Foundation

protocol SpacesClientProtocol {
    func list() async throws -> [SpaceDTO]
    func get(id: UUID) async throws -> SpaceDTO
    func create(_ request: CreateSpaceRequest) async throws -> SpaceDTO
    func update(id: UUID, _ request: UpdateSpaceRequest) async throws -> SpaceDTO
    func delete(id: UUID) async throws
}
