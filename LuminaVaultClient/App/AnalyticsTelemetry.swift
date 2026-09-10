// LuminaVaultClient/LuminaVaultClient/App/AnalyticsTelemetry.swift
//
// Production sinks for the two failure seams:
//
// - `AnalyticsTelemetry` is the `TelemetryProtocol` the app injects into
//   feature view models. Every event goes to the unified log (via
//   `LoggerTelemetry`) and PostHog; `*_failed` events are additionally
//   captured in Sentry with the properties as tags, so a failed chat send
//   is searchable by status, transport and endpoint.
// - `RequestFailureBreadcrumbs` turns `BaseHTTPClient.onRequestFailure`
//   into a Sentry breadcrumb, so whatever is captured next carries the
//   last failed requests (method, path, status, server message).
//
// Neither ever receives a request body, an auth header, or user content —
// `APIRequestFailure` and `ChatViewModel.recordFailedSend` guarantee that
// upstream.

import Foundation
import PostHog
import Sentry

struct AnalyticsTelemetry: TelemetryProtocol {
    private let logger = LoggerTelemetry()

    func track(_ event: String, properties: [String: String]) {
        logger.track(event, properties: properties)
        PostHogSDK.shared.capture(event, properties: properties)
        guard event.hasSuffix("_failed") else { return }
        SentrySDK.capture(message: event) { scope in
            scope.setLevel(.error)
            for (key, value) in properties {
                scope.setTag(value: value, key: key)
            }
        }
    }
}

enum RequestFailureBreadcrumbs {
    static func record(_ failure: APIRequestFailure) {
        let crumb = Breadcrumb(level: .error, category: "http")
        crumb.type = "http"
        crumb.message = "\(failure.method) \(failure.path)"
        var data: [String: Any] = [
            "kind": failure.kind.rawValue,
            "method": failure.method,
            "path": failure.path,
        ]
        if let status = failure.statusCode {
            data["status_code"] = status
        }
        if !failure.detail.isEmpty {
            data["detail"] = failure.detail
        }
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }
}
