// LuminaVaultClient/LuminaVaultClientTests/Mocks/WaitUntil.swift
//
// Condition-based waiting for main-actor view-model tests.
//
// A fixed `Task.sleep(for: .milliseconds(150))` after `send()` passes on a
// developer Mac and fails on a starved CI runner — `ChatViewModelTransportTests`
// took ten seconds for one test there and the reply had not landed when the
// sleep ended. Poll for the state the assertion needs instead; the test still
// fails fast, with a message, if it never arrives.

import XCTest

/// Polls `condition` on the main actor every 10 ms until it is true or
/// `timeout` elapses, then fails the test at the call site.
@MainActor
func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            XCTFail("Timed out after \(timeout) waiting for \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
