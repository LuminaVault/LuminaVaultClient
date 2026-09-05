// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunTrail.swift
//
// Hermes Companion Phase 1 — turns the raw run event feed into something a
// person can read.
//
// `HermesRunEventDTO.payload` is whatever Hermes sent, kept verbatim so the
// server can replay a run byte-for-byte. That is the right storage decision
// and the wrong display one: the screen needs a line per meaningful step, so
// this file owns the translation. It is a UI model, not a DTO — the wire
// types all come from LuminaVaultShared.
//
// `message.delta` is deliberately not a trail row. Deltas arrive one token at
// a time, so rendering them as rows would produce hundreds of one-character
// entries; `HermesRunDetailViewModel` folds them into a single streaming
// answer instead.

import Foundation
import LuminaVaultShared

/// One readable step in a run.
struct HermesRunTrailItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case lifecycle
        case tool
        case approval
        case failure
        case success
    }

    /// The event `seq` — monotonic per run, so it doubles as the resume
    /// cursor and as a stable identity across reconnects.
    let id: Int
    let kind: Kind
    let title: String
    let detail: String?
    let at: Date

    var systemImage: String {
        switch kind {
        case .lifecycle: return "circle.dotted"
        case .tool: return "wrench.and.screwdriver"
        case .approval: return "hand.raised.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
}

extension HermesRunTrailItem {
    /// `nil` for events that are folded elsewhere (`message.delta`) rather
    /// than shown as their own step.
    init?(event: HermesRunEventDTO) {
        let fields = event.payload.lvObject ?? [:]

        func tool() -> String? {
            fields["tool"]?.lvString ?? fields["tool_name"]?.lvString
        }

        switch event.event {
        case "message.delta", "assistant.delta", "message.started":
            return nil

        case "run.started":
            self.init(id: event.seq, kind: .lifecycle, title: "Run started", detail: nil, at: event.at)

        case "tool.started":
            self.init(
                id: event.seq,
                kind: .tool,
                title: tool().map { "Running \($0)" } ?? "Running a tool",
                detail: fields["preview"]?.lvString,
                at: event.at
            )

        case "tool.completed":
            let failed = fields["error"]?.lvBool ?? false
            let seconds = fields["duration"]?.lvDouble
            self.init(
                id: event.seq,
                kind: failed ? .failure : .tool,
                title: tool().map { failed ? "\($0) failed" : "\($0) finished" }
                    ?? (failed ? "Tool failed" : "Tool finished"),
                detail: seconds.map { String(format: "%.1fs", $0) },
                at: event.at
            )

        case "tool.failed":
            self.init(
                id: event.seq,
                kind: .failure,
                title: tool().map { "\($0) failed" } ?? "Tool failed",
                detail: fields["error"]?.lvString ?? fields["preview"]?.lvString,
                at: event.at
            )

        case "hermes.tool.progress", "tool.progress", "reasoning.available":
            let text = fields["text"]?.lvString ?? fields["delta"]?.lvString ?? fields["preview"]?.lvString
            guard let text, !text.isEmpty else { return nil }
            self.init(
                id: event.seq,
                kind: .tool,
                title: tool() ?? "Working",
                detail: text,
                at: event.at
            )

        case "approval.request":
            self.init(
                id: event.seq,
                kind: .approval,
                title: "Waiting for your approval",
                detail: fields["command"]?.lvString,
                at: event.at
            )

        case "approval.responded":
            let choice = fields["choice"]?.lvString
            self.init(
                id: event.seq,
                kind: .approval,
                title: choice.map { "You answered \($0)" } ?? "Approval answered",
                detail: nil,
                at: event.at
            )

        case "run.completed":
            self.init(id: event.seq, kind: .success, title: "Run finished", detail: nil, at: event.at)

        case "run.failed":
            self.init(
                id: event.seq,
                kind: .failure,
                title: "Run failed",
                detail: fields["error"]?.lvString,
                at: event.at
            )

        case "run.cancelled":
            self.init(id: event.seq, kind: .lifecycle, title: "Run stopped", detail: nil, at: event.at)

        case "error":
            self.init(
                id: event.seq,
                kind: .failure,
                title: "Hermes reported an error",
                detail: fields["message"]?.lvString ?? fields["error"]?.lvString,
                at: event.at
            )

        default:
            // Anything Hermes gains later still shows, named, rather than
            // vanishing from the trail.
            self.init(id: event.seq, kind: .lifecycle, title: event.event, detail: nil, at: event.at)
        }
    }

    /// The assistant text this event contributes, if any. Folded into one
    /// streaming answer by the detail view model.
    static func messageDelta(in event: HermesRunEventDTO) -> String? {
        switch event.event {
        case "message.delta", "assistant.delta":
            return event.payload.lvObject?["delta"]?.lvString
        default:
            return nil
        }
    }
}

/// Read accessors for `AnyJSONValue`. The shared package ships the type
/// without them (the server keeps its own copy), and the client needs to
/// look inside an event payload without unwrapping five levels of `case let`
/// at every call site. Prefixed to avoid colliding if the shared package
/// ever grows its own.
extension AnyJSONValue {
    var lvString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var lvDouble: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var lvBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var lvObject: [String: AnyJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
