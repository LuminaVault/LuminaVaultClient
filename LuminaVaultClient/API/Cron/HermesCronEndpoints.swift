// LuminaVaultClient/LuminaVaultClient/API/Cron/HermesCronEndpoints.swift
//
// Hermes cron bridge — list the connected Hermes's cron jobs (managed via exec,
// or BYO via the dashboard API; the server picks the transport). Field names
// are camelCase to match the server's default JSON encoder.

import Foundation

struct HermesCronJobDTO: Decodable, Identifiable {
    let id: String
    let name: String?
    let schedule: String?
    let deliver: String?
    let lastRun: String?
    let status: String?
    let mode: String?   // "agent" | "script"
}

struct HermesCronListDTO: Decodable {
    let source: String   // "managed" | "byo"
    let jobs: [HermesCronJobDTO]
}

enum HermesCronEndpoints {
    struct List: Endpoint {
        typealias Response = HermesCronListDTO
        var path: String { "/v1/me/hermes/cron" }
        var method: HTTPMethod { .get }
    }
}
