// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentTerminalTranscript.swift
//
// What the agent ran in its terminal, rebuilt from the run's events.
//
// Hermes (LuminaVaultHermesAgent#14) puts the terminal tool's `command` on
// `tool.started`, its `output`, `exit_code` and `output_truncated` on
// `tool.completed`, and streams background-process output as
// `terminal.output` chunks keyed by `process_id`. Nothing new is stored: this
// is a pure fold over the event rows the run feed already replays, so a
// reconnect rebuilds exactly the same transcript.
//
// An older Hermes sends none of these fields and the transcript stays empty,
// so the view renders nothing rather than a terminal full of blanks.
//
// A port of the web `src/lib/chat/terminal-transcript.ts`: one contract, two
// renderers. iOS reads the raw snake_case payload; the web decoder
// camel-cases it, so the web copy accepts both spellings.

import Foundation
import LuminaVaultShared

enum AgentTerminalEntry: Equatable, Sendable, Identifiable {
    case command(Command)
    case process(Process)

    struct Command: Equatable, Sendable {
        /// The `tool.started` seq — stable across replays.
        let seq: Int
        let command: String
        let background: Bool
        /// `nil` while the command is still running.
        var output: String?
        var exitCode: Int?
        var outputTruncated = false
        var failed = false
    }

    struct Process: Equatable, Sendable {
        /// The seq of the first chunk seen for this process.
        let seq: Int
        let processID: String
        var output: String
        /// Hermes stopped streaming this run's background output at its budget.
        var truncated: Bool
    }

    var id: String {
        switch self {
        case let .command(command): "command:\(command.seq)"
        case let .process(process): "process:\(process.processID)"
        }
    }
}

enum AgentTerminalTranscript {
    /// The client's own ceiling per process, so a long-lived screen cannot
    /// grow without bound. Hermes already caps a run at 256k characters.
    static let maxProcessCharacters = 256_000

    private static let terminalTool = "terminal"

    /// Folds one event in. Returns `nil` when the event contributes nothing,
    /// so a caller can skip an observable write.
    static func apply(_ event: HermesRunEventDTO, to entries: [AgentTerminalEntry]) -> [AgentTerminalEntry]? {
        let fields = event.payload.lvObject ?? [:]
        let tool = fields["tool"]?.lvString ?? fields["tool_name"]?.lvString

        switch event.event {
        case "tool.started":
            guard tool == terminalTool, let command = fields["command"]?.lvString, !command.isEmpty else { return nil }
            return entries + [.command(.init(
                seq: event.seq,
                command: command,
                background: fields["background"]?.lvBool ?? false
            )),]

        case "tool.completed", "tool.failed":
            guard tool == terminalTool else { return nil }
            // One tool at a time per run, so a completion closes the oldest
            // command still open.
            guard let index = entries.firstIndex(where: {
                if case let .command(command) = $0 { return command.output == nil }
                return false
            }), case var .command(open) = entries[index] else { return nil }

            let exit = fields["exit_code"]?.lvDouble.map { Int($0) }
            // `error` is a bool on `tool.completed` and a message on `tool.failed`.
            let errorText = fields["error"]?.lvString
            open.output = fields["output"]?.lvString ?? errorText ?? ""
            open.exitCode = exit
            open.outputTruncated = fields["output_truncated"]?.lvBool ?? false
            open.failed = event.event == "tool.failed"
                || fields["error"]?.lvBool == true
                || (exit.map { $0 != 0 } ?? false)
            var next = entries
            next[index] = .command(open)
            return next

        case "terminal.output":
            guard let processID = fields["process_id"]?.lvString, !processID.isEmpty else { return nil }
            let chunk = fields["chunk"]?.lvString ?? ""
            let truncated = fields["truncated"]?.lvBool ?? false
            if let index = entries.firstIndex(where: {
                if case let .process(process) = $0 { return process.processID == processID }
                return false
            }), case var .process(process) = entries[index] {
                process.output += chunk
                if process.output.count > maxProcessCharacters {
                    process.output = String(process.output.suffix(maxProcessCharacters))
                }
                process.truncated = process.truncated || truncated
                var next = entries
                next[index] = .process(process)
                return next
            }
            guard !chunk.isEmpty || truncated else { return nil }
            return entries + [.process(.init(seq: event.seq, processID: processID, output: chunk, truncated: truncated))]

        default:
            return nil
        }
    }

    static func build(_ events: [HermesRunEventDTO]) -> [AgentTerminalEntry] {
        events.reduce(into: []) { entries, event in
            if let next = apply(event, to: entries) { entries = next }
        }
    }
}
