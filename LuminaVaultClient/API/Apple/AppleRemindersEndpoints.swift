// LuminaVaultClient/LuminaVaultClient/API/Apple/AppleRemindersEndpoints.swift
//
// Apple Reminders (EventKit) selective-sync ingest.
//   POST /v1/reminders/sync — push EventKit reminder deltas into the
//   server-side `apple_reminders` cache the Hermes `reminders_list` tool reads.
//
// Uses the DEFAULT JSONEncoder (camelCase keys + `.deferredToDate` dates).
// The server decodes `AppleRemindersSyncRequest` with Hummingbird's default
// `JSONDecoder` — also camelCase + `.deferredToDate` — so the two are
// symmetric. Do NOT swap in `.lvHealth`: its `.convertToSnakeCase` would
// rename `externalID`→`external_id` etc. and the server-side fields would
// decode nil (see memory: server_request_decoder_no_snakecase).

import Foundation
import LuminaVaultShared

enum AppleRemindersEndpoints {
    struct Sync: Endpoint {
        typealias Response = AppleSyncResponse
        let reminders: [AppleReminderInput]

        var path: String { "/v1/reminders/sync" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { true }
        var body: (any Encodable)? { AppleRemindersSyncRequest(reminders: reminders) }
    }
}
