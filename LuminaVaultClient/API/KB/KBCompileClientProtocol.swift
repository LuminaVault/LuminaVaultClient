// LuminaVaultClient/LuminaVaultClient/API/KB/KBCompileClientProtocol.swift
// HER-36: kb-compile is the only KB endpoint right now. Other kb-* commands
// (ingest, healthcheck, reindex, clean) ride future tickets.
import LuminaVaultShared

protocol KBCompileClientProtocol {
    /// Triggers a kb-compile pass. With a default `KBCompileRequest()` the
    /// server compiles every vault file that has not been processed yet —
    /// the one-tap UX behind the "Sync & Learn" button.
    func compile(_ request: KBCompileRequest) async throws -> KBCompileResponse
}
