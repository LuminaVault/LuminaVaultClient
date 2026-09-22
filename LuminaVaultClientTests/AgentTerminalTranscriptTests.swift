// LuminaVaultClient/LuminaVaultClientTests/AgentTerminalTranscriptTests.swift
//
// The fold behind the agent terminal. Mirrors the web
// `terminal-transcript.test.ts` case for case, because the two read one
// contract (LuminaVaultHermesAgent#14).

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class AgentTerminalTranscriptTests: XCTestCase {
    private var seq = 0

    private func event(_ name: String, _ fields: [String: AnyJSONValue]) -> HermesRunEventDTO {
        seq += 1
        return .stub(seq: seq, event: name, fields: fields)
    }

    private func command(_ entries: [AgentTerminalEntry], _ index: Int = 0) -> AgentTerminalEntry.Command? {
        if case let .command(command) = entries[index] { return command }
        return nil
    }

    func testPairsACommandWithItsOutputAndExitCode() throws {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("ls")]),
            event("tool.completed", ["tool": .string("terminal"), "output": .string("a.txt"), "exit_code": .number(0)]),
        ])
        let entry = try XCTUnwrap(command(entries))
        XCTAssertEqual(entry.command, "ls")
        XCTAssertEqual(entry.output, "a.txt")
        XCTAssertEqual(entry.exitCode, 0)
        XCTAssertFalse(entry.failed)
    }

    func testANonZeroExitIsAFailure() throws {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("false")]),
            event("tool.completed", [
                "tool": .string("terminal"), "output": .string(""), "exit_code": .number(1),
                "output_truncated": .bool(true),
            ]),
        ])
        let entry = try XCTUnwrap(command(entries))
        XCTAssertEqual(entry.exitCode, 1)
        XCTAssertTrue(entry.failed)
        XCTAssertTrue(entry.outputTruncated)
    }

    func testARunningCommandHasNoOutputYet() throws {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("sleep 5")]),
        ])
        XCTAssertNil(try XCTUnwrap(command(entries)).output)
    }

    func testCommandsCloseOldestFirst() {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("one")]),
            event("tool.completed", ["tool": .string("terminal"), "output": .string("first")]),
            event("tool.started", ["tool": .string("terminal"), "command": .string("two")]),
            event("tool.completed", ["tool": .string("terminal"), "output": .string("second")]),
        ])
        XCTAssertEqual(command(entries, 0)?.output, "first")
        XCTAssertEqual(command(entries, 1)?.output, "second")
    }

    func testOtherToolsContributeNothing() {
        XCTAssertTrue(AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("read_file"), "preview": .string("x")]),
            event("tool.completed", ["tool": .string("read_file"), "output": .string("y")]),
        ]).isEmpty)
    }

    /// An older Hermes sends the tool events with no `command`: no blanks.
    func testAHermesWithoutTerminalOutputRendersNothing() {
        XCTAssertTrue(AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "preview": .string("ls")]),
            event("tool.completed", ["tool": .string("terminal"), "duration": .number(0.1), "error": .bool(false)]),
        ]).isEmpty)
    }

    func testAFailedToolCarriesItsErrorText() throws {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("rm -rf /")]),
            event("tool.failed", ["tool": .string("terminal"), "error": .string("blocked by policy")]),
        ])
        let entry = try XCTUnwrap(command(entries))
        XCTAssertTrue(entry.failed)
        XCTAssertEqual(entry.output, "blocked by policy")
    }

    func testBackgroundChunksAppendPerProcess() {
        let entries = AgentTerminalTranscript.build([
            event("terminal.output", ["process_id": .string("p1"), "chunk": .string("listening\n")]),
            event("terminal.output", ["process_id": .string("p2"), "chunk": .string("other\n")]),
            event("terminal.output", ["process_id": .string("p1"), "chunk": .string("GET /\n")]),
        ])
        let outputs = entries.compactMap { entry -> String? in
            if case let .process(process) = entry { return "\(process.processID):\(process.output)" }
            return nil
        }
        XCTAssertEqual(outputs, ["p1:listening\nGET /\n", "p2:other\n"])
    }

    func testTheBudgetMarkerIsKept() {
        let entries = AgentTerminalTranscript.build([
            event("terminal.output", ["process_id": .string("p1"), "chunk": .string("x")]),
            event("terminal.output", ["process_id": .string("p1"), "chunk": .string(""), "truncated": .bool(true)]),
        ])
        guard case let .process(process) = entries.first else { return XCTFail("expected a process") }
        XCTAssertTrue(process.truncated)
        XCTAssertEqual(process.output, "x")
    }

    func testAnUnrelatedEventReturnsNil() {
        XCTAssertNil(AgentTerminalTranscript.apply(event("message.delta", ["delta": .string("hi")]), to: []))
    }

    @MainActor
    func testTheFollowerFoldsTerminalEventsAsTheyArrive() async {
        let follower = ChatRunFollower(client: StubHermesRunsClient(), runID: UUID())
        follower.apply(event("tool.started", ["tool": .string("terminal"), "command": .string("ls")]))
        follower.apply(event("tool.completed", ["tool": .string("terminal"), "output": .string("a"), "exit_code": .number(0)]))
        XCTAssertEqual(follower.terminal.count, 1)
        XCTAssertEqual(follower.toolCallCount, 1)
    }

    func testCopiedTextReadsLikeATerminal() {
        let entries = AgentTerminalTranscript.build([
            event("tool.started", ["tool": .string("terminal"), "command": .string("ls")]),
            event("tool.completed", ["tool": .string("terminal"), "output": .string("a.txt")]),
        ])
        XCTAssertEqual(AgentTerminalView.plainText(entries), "$ ls\na.txt")
    }
}
