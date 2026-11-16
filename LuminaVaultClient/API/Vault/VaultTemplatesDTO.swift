// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultTemplatesDTO.swift
// Backlog E6.4: daily notes and templates. Mirrors the Go spec's
// `VaultTemplatesSeedResponse` and `VaultFromTemplateRequest`. Templates are
// notes in the server's Templates Space (`templates/`), daily notes live in
// the Daily Space (`daily/YYYY-MM-DD.md`); the server renders `{{date}}`,
// `{{time}}`, `{{title}}` and `{{space}}`.
import Foundation

nonisolated struct VaultTemplatesSeedResponse: Decodable, Sendable, Equatable {
    let spaceId: UUID
    /// File names this call wrote; empty when every starter already existed.
    let created: [String]
}

/// Plain `JSONEncoder` keeps these keys camelCase, which the Go struct needs.
nonisolated struct VaultFromTemplateRequest: Encodable, Sendable, Equatable {
    /// A file name in `templates/`, e.g. `meeting.md`.
    let template: String
    let title: String
    var spaceId: UUID?
    /// IANA zone for `{{date}}` and `{{time}}`.
    var tz: String?
}
