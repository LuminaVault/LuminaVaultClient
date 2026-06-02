// LuminaVaultClient/LuminaVaultClient/API/Integrations/IntegrationsClientProtocol.swift
//
// HER-240b — public surface for `/v1/integrations/xai`. Protocol-shaped
// so ViewModels can be tested against a fake without spinning the real
// HTTP stack.

import Foundation

protocol IntegrationsClientProtocol: Sendable {
    /// Returns the tenant's current xAI Grok OAuth state. Never returns
    /// `nil`; an unconnected user gets `connected == false`.
    func getXaiStatus() async throws -> XaiStatusResponse

    /// Spawns (or reuses) the tenant's Hermes container, drives the CLI to
    /// produce the authorize URL, returns `(sessionID, authorizeURL)`. The
    /// iOS app opens the URL in a `WKWebView`.
    func startXaiConnect() async throws -> XaiStartResponse

    /// Forwards the captured loopback callback URL to the running Hermes
    /// process, awaits its clean exit, returns the new status (tier flips
    /// to `pro` on success).
    func completeXaiConnect(sessionID: String, callbackURL: String) async throws -> XaiStatusResponse

    /// Tears down the xai-oauth session inside the tenant's Hermes container
    /// and demotes tier back to `trial`.
    func disconnectXai() async throws -> XaiStatusResponse

    // MARK: - Nous Portal subscription (OAuth device-code)

    /// Returns the tenant's current Nous Portal connection state. Never
    /// returns `nil`; an unconnected user gets `connected == false`.
    func getNousStatus() async throws -> NousStatusResponse

    /// Spawns (or reuses) the tenant's Hermes container, drives the CLI to
    /// produce the device verification URL + user-code, returns them. The
    /// iOS app opens the URL in a browser for the user to approve.
    func startNousConnect() async throws -> NousStartResponse

    /// Awaits the in-container CLI's exit after the user approves in their
    /// browser (the CLI polls Nous and self-completes). Returns the new
    /// status with `connected == true` on success.
    func completeNousConnect(sessionID: String) async throws -> NousStatusResponse

    /// Runs `hermes auth remove nous` inside the tenant's container and
    /// clears the connection marker → managed-Hermes fallback.
    func disconnectNous() async throws -> NousStatusResponse
}
