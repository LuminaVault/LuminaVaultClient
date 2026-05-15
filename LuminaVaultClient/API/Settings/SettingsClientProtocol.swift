// LuminaVaultClient/LuminaVaultClient/API/Settings/SettingsClientProtocol.swift
//
// HER-218 — BYO-Hermes Settings client. Surfaces 404 as a `nil` config
// rather than throwing — the empty state is a first-class part of the
// ViewModel's state machine.

import Foundation

protocol SettingsClientProtocol {
    /// `nil` when the server returns 404 (no config). Other HTTP errors
    /// propagate as `APIError.httpError`.
    func getHermesConfig() async throws -> HermesConfigGetResponse?
    func putHermesConfig(baseUrl: String, authHeader: String?) async throws -> HermesConfigGetResponse
    func deleteHermesConfig() async throws
    func testHermesConfig() async throws -> HermesConfigTestResponse
}
