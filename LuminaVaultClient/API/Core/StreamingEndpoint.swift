// LuminaVaultClient/LuminaVaultClient/API/Core/StreamingEndpoint.swift
//
// HER-269 — Server-Sent Events endpoint contract. The server emits
// `text/event-stream` where each event is a single `data:` JSON line
// decodable as `Event`. Used by /v1/conversations/:id/messages/stream
// and /v1/query/stream (QueryStreamEvent) and is wide enough to support
// any future SSE endpoint by varying the `Event` associated type.
//
// Frame parsing rules implemented by `BaseHTTPClient.executeStream`:
//   - Each line ending (`\n`, `\r`, or `\r\n`) is a field separator.
//   - `data:` (optional space) appends to the current event buffer.
//   - Lines starting with `:` are comments and ignored.
//   - `event:`, `id:`, `retry:` fields are ignored (not used by LVS).
//   - A blank line flushes the buffer as one event.
//   - The literal payload `[DONE]` terminates the stream gracefully
//     (mirrors the OpenAI sentinel; LVS's own QueryStreamEvent emits a
//     typed `done` case which the consumer handles as a graceful end).
import Foundation

protocol StreamingEndpoint: Sendable {
    associatedtype Event: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: (any Encodable & Sendable)? { get }
    var requiresAuth: Bool { get }
    var decoder: JSONDecoder { get }
    var encoder: JSONEncoder { get }
    /// Per-request connect/idle timeout for the SSE request. Streaming
    /// replies (LLM token streams) can be slow to emit their first byte —
    /// especially a cold managed brain — so this defaults well above the
    /// 60s `URLSession.shared` default to avoid a premature
    /// `URLError.timedOut` before any token arrives.
    var streamTimeout: TimeInterval { get }
}

extension StreamingEndpoint {
    var requiresAuth: Bool { true }
    var body: (any Encodable & Sendable)? { nil }
    var decoder: JSONDecoder { .hvDefault }
    var encoder: JSONEncoder { JSONEncoder() }
    var streamTimeout: TimeInterval { 120 }
}

/// Pure SSE line-buffer state machine. Extracted so the wire parser can
/// be unit-tested in isolation from `URLSession.bytes(for:)`, which does
/// not play well with `URLProtocol`-based mocks under XCTest.
///
/// Usage:
/// ```swift
/// var parser = SSEFrameParser()
/// for line in lines {
///     switch try parser.feed(line: line) {
///     case .event(let data): /* decode `data` as Event */
///     case .done: /* terminator hit, stop reading */
///     case .pending: /* keep feeding */
///     }
/// }
/// ```
struct SSEFrameParser: Sendable {
    enum Outcome: Equatable, Sendable {
        case pending
        case event(Data)
        case done
    }

    private var buffer = ""
    /// Bytes of the current, not-yet-terminated wire line. SSE frames are
    /// delimited by blank lines, so framing MUST be done at the byte level:
    /// `URLSession.AsyncBytes.lines` (AsyncLineSequence) silently drops
    /// empty lines, which are exactly the frame delimiters `feed(line:)`
    /// relies on. Splitting bytes here preserves them.
    private var lineBytes: [UInt8] = []

    /// Feed raw transport bytes. Splits on LF (stripping a trailing CR),
    /// preserving blank lines, and runs each completed line through
    /// `feed(line:)`. Returns the outcomes for lines completed by these
    /// bytes (callers act on `.event` / `.done`, ignore `.pending`).
    ///
    /// This is the transport entry point. Do NOT route the byte stream
    /// through `AsyncLineSequence` — it discards the blank-line frame
    /// delimiters and the parser then concatenates the entire stream into
    /// one buffer ("Unexpected character '{' after top-level value").
    mutating func feed(bytes: some Sequence<UInt8>) -> [Outcome] {
        var outcomes: [Outcome] = []
        for byte in bytes {
            if byte == 0x0A { // LF terminates a line
                outcomes.append(consumeLineBytes())
            } else {
                lineBytes.append(byte)
            }
        }
        return outcomes
    }

    /// Call once the byte stream ends. Drains a trailing partial line (no
    /// final LF) and then any buffered frame, so the last event is never
    /// dropped. Returns non-`.pending` outcomes in order.
    mutating func finishBytes() -> [Outcome] {
        var outcomes: [Outcome] = []
        if !lineBytes.isEmpty {
            outcomes.append(consumeLineBytes())
        }
        let flushed = flush()
        if case .pending = flushed {} else { outcomes.append(flushed) }
        return outcomes
    }

    private mutating func consumeLineBytes() -> Outcome {
        if lineBytes.last == 0x0D { lineBytes.removeLast() } // strip CR
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)
        return feed(line: line)
    }

    /// Append one SSE wire line to the parser. Returns:
    /// - `.event(data)` when a blank line flushes a non-empty buffer
    /// - `.done` when the buffer was the literal `[DONE]` sentinel
    /// - `.pending` otherwise (line absorbed, no event yet)
    mutating func feed(line: String) -> Outcome {
        if line.isEmpty {
            if buffer.isEmpty { return .pending }
            let payload = buffer
            buffer.removeAll(keepingCapacity: true)
            if payload == "[DONE]" { return .done }
            return .event(Data(payload.utf8))
        }
        if line.hasPrefix(":") { return .pending }
        if line.hasPrefix("data:") {
            let start = line.index(line.startIndex, offsetBy: 5)
            let rest = line[start...]
            let chunk = rest.first == " " ? String(rest.dropFirst()) : String(rest)
            if !buffer.isEmpty { buffer.append("\n") }
            buffer.append(chunk)
        }
        // event:/id:/retry: and any other field — ignored per LVS contract.
        return .pending
    }

    /// Called when the upstream byte stream ends without a trailing blank
    /// line. If the buffer holds an unfinished payload, treat it as one
    /// final event so we don't drop the last frame.
    mutating func flush() -> Outcome {
        guard !buffer.isEmpty else { return .pending }
        let payload = buffer
        buffer.removeAll(keepingCapacity: true)
        if payload == "[DONE]" { return .done }
        return .event(Data(payload.utf8))
    }
}
