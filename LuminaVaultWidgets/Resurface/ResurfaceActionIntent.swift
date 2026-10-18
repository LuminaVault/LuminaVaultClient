//
//  ResurfaceActionIntent.swift
//  LuminaVaultWidgets
//
//  Soon / Later / Never on the "Today's memory" widget.
//
//  Runs in the widget extension, which links neither LuminaVaultShared nor
//  the app's HTTP stack: the review is one small POST, authenticated with the
//  access token the app mirrors into the shared keychain group. On success
//  the answered memory leaves the App Group snapshot and the next one shows;
//  on failure (offline, or a token that expired while the app was closed)
//  the widget is left as it was, so the memory is still there to answer.
//

import AppIntents
import Foundation
import OSLog
import WidgetKit

nonisolated private let log = Logger(subsystem: "com.luminavault", category: "resurface-widget")

/// The answers the widget offers. Raw values are the server's
/// `MemoryReviewAction` wire values.
enum ResurfaceWidgetAction: String, AppEnum {
    case soon
    case later
    case never

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Review action"
    static let caseDisplayRepresentations: [ResurfaceWidgetAction: DisplayRepresentation] = [
        .soon: "Soon",
        .later: "Later",
        .never: "Never",
    ]
}

struct ResurfaceActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer today's memory"
    /// A widget button, not a Shortcuts action.
    static let isDiscoverable = false

    @Parameter(title: "Memory")
    var memoryID: String

    @Parameter(title: "Action")
    var action: ResurfaceWidgetAction

    init() {}

    init(memoryID: UUID, action: ResurfaceWidgetAction) {
        self.memoryID = memoryID.uuidString
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: memoryID) else { return .result() }
        do {
            try await WidgetReviewClient().review(memoryID: id, action: action.rawValue)
            ResurfaceWidgetStore.shared.remove(memoryId: id)
            WidgetCenter.shared.reloadTimelines(ofKind: ResurfaceWidgetStore.widgetKind)
        } catch {
            log.error("widget review failed: \(String(describing: error), privacy: .public)")
        }
        return .result()
    }
}

/// `POST /v1/memory/{id}/review` with `{"action": …}`, and nothing else.
struct WidgetReviewClient: Sendable {
    enum ReviewError: Error {
        case missingToken
        case badStatus(Int)
    }

    var session: URLSession = .shared
    var baseURL: URL = ExtensionAPIConfig.apiBaseURL
    var tokenProvider: @Sendable () -> String? = { ExtensionAPIConfig.sharedAccessToken }

    func review(memoryID: UUID, action: String) async throws {
        let request = try makeRequest(memoryID: memoryID, action: action)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw ReviewError.badStatus(http.statusCode) }
    }

    func makeRequest(memoryID: UUID, action: String) throws -> URLRequest {
        guard let token = tokenProvider(), !token.isEmpty else { throw ReviewError.missingToken }
        let url = baseURL.appendingPathComponent("v1/memory/\(memoryID.uuidString.lowercased())/review")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["action": action])
        request.timeoutInterval = 15
        return request
    }
}
