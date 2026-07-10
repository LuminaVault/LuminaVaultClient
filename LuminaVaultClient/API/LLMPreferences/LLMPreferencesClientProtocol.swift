// LuminaVaultClient/LuminaVaultClient/API/LLMPreferences/LLMPreferencesClientProtocol.swift
//
// HER-252 — per-user LLM routing preference client (primary model +
// ordered fallback chain). Server always returns 200 (defaults when no
// row exists) so callers don't need 404 handling.

import Foundation
import LuminaVaultShared

protocol LLMPreferencesClientProtocol {
    func get() async throws -> LLMPreferencesGetResponse
    func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse
}

protocol RouterClientProtocol: Sendable {
    func profiles() async throws -> RouterProfilesResponse
    func catalog() async throws -> RouterCatalogResponse
    func dashboard() async throws -> RouterDashboardResponse
    func updateProfile(id: UUID, request: RouterProfileWriteRequest) async throws -> RouterProfileDTO
    func bindings() async throws -> RouterBindingsResponse
    func bind(scope: RouterBindingScope, scopeID: String, profileID: UUID) async throws -> RouterBindingDTO
    func unbind(scope: RouterBindingScope, scopeID: String) async throws
}
