// The Brain tab's ways in: an entry request (Show in graph, the `brain` deep
// link) is applied once, replaces a focus already set, and uppercases ids; the
// active vault is re-read when the tab returns, and a change discards the
// reasoning answer and nothing else.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
struct BrainEntryTests {
    private static let memory = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD") ?? UUID()

    // MARK: entry request

    @Test func aMemoryEntryFocusesItsUppercasedId() {
        let lower = UUID(uuidString: memoryLower) ?? UUID()
        let entry = BrainEntryRequest.memory(lower, after: nil)
        #expect(entry.focus == "0A1B2C3D-0000-4000-8000-00000000ABCD")
    }

    private let memoryLower = "0a1b2c3d-0000-4000-8000-00000000abcd"

    @Test func anIdIsUppercasedWhereverAUuidSitsInIt() {
        #expect(BrainEntryRequest.normalized(memoryLower) == "0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(BrainEntryRequest.normalized("space:\(memoryLower)") == "space:0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(BrainEntryRequest.normalized("tag:home") == "tag:home")
        #expect(BrainEntryRequest.normalized("N1") == "N1")
    }

    @Test func tokensAlwaysGrow() {
        let first = BrainEntryRequest.memory(Self.memory, after: nil)
        let second = BrainEntryRequest.memory(Self.memory, after: first)
        #expect(second.token > first.token)
        #expect(second != first, "the same memory twice is two requests")
    }

    @Test func aFreshRequestIsAppliedAtTheDefaultDepth() throws {
        let entry = BrainEntryRequest.memory(Self.memory, after: nil)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: nil))
        #expect(applied.focus == "0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(applied.depth == 1)
        #expect(applied.token == entry.token)
    }

    @Test func aRequestIsAppliedOnce() throws {
        let entry = BrainEntryRequest.memory(Self.memory, after: nil)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: nil))
        #expect(BrainEntryRequest.apply(entry, lastApplied: applied.token) == nil)
        #expect(BrainEntryRequest.apply(nil, lastApplied: nil) == nil)
    }

    @Test func aNewRequestReplacesTheFocusAlreadySet() throws {
        let first = BrainEntryRequest.memory(Self.memory, after: nil)
        let second = BrainEntryRequest(focus: "N7", token: first.token + 1)
        let applied = try #require(BrainEntryRequest.apply(second, lastApplied: first.token))
        #expect(applied.focus == "N7")
    }

    @Test func anEntryWithNoFocusMeansTheFullGraph() throws {
        let entry = BrainEntryRequest(focus: nil, token: 3)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: 2))
        #expect(applied.focus == nil)
        #expect(applied.depth == 1)
    }

    // MARK: active vault

    @Test func theFirstReadIsNotAChange() {
        var tracker = BrainActiveVaultTracker()
        #expect(tracker.observe(Self.memory) == false)
        #expect(tracker.current == Self.memory)
    }

    @Test func aDifferentVaultOnTheNextReadIsAChange() {
        var tracker = BrainActiveVaultTracker()
        _ = tracker.observe(Self.memory)
        #expect(tracker.observe(Self.memory) == false)
        #expect(tracker.observe(UUID()) == true)
        #expect(tracker.observe(nil) == true)
        #expect(tracker.observe(nil) == false)
    }

    @Test func aFirstReadOfNoVaultThenAVaultIsAChange() {
        var tracker = BrainActiveVaultTracker()
        _ = tracker.observe(nil)
        #expect(tracker.observe(Self.memory) == true)
    }

    @Test func theTrayExplainsInTheNewVaultAfterAChange() {
        var tracker = BrainActiveVaultTracker()
        let old = UUID(), new = UUID()
        _ = tracker.observe(old)
        _ = tracker.observe(new)
        #expect(tracker.current == new)
    }
}
