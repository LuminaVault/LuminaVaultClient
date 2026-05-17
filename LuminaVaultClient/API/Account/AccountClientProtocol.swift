// LuminaVaultClient/LuminaVaultClient/API/Account/AccountClientProtocol.swift
// HER-212: DELETE /v1/account — GDPR hard-delete (cascades to all tenant data).
import Foundation

protocol AccountClientProtocol {
    func deleteAccount() async throws
}
