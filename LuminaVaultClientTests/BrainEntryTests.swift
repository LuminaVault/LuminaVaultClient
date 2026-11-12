// The Brain tab's ways in: an entry request (Show in graph, the `brain` deep
// link) is applied once, replaces a focus already set, uppercases ids, clears
// the vault filter when it names a focus, and is acknowledged once applied;
// the active vault is re-read when the tab returns, and a change moves the
// reasoning sheet's target to the new vault.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
struct BrainEntryTests {
    private static let memory = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD") ?? UUID()
    private let memoryLower = "0a1b2c3d-0000-4000-8000-00000000abcd"

    // MARK: entry request

    @Test func aMemoryEntryFocusesItsUppercasedId() {
        let lower = UUID(uuidString: memoryLower) ?? UUID()
        let entry = BrainEntryRequest.memory(lower, afterToken: 0)
        #expect(entry.focus == "0A1B2C3D-0000-4000-8000-00000000ABCD")
    }

    @Test func anIdIsUppercasedWhereverAUuidSitsInIt() {
        #expect(BrainEntryRequest.normalized(memoryLower) == "0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(BrainEntryRequest.normalized("space:\(memoryLower)") == "space:0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(BrainEntryRequest.normalized("tag:home") == "tag:home")
        #expect(BrainEntryRequest.normalized("N1") == "N1")
    }

    @Test func nextAlwaysGrowsTheToken() {
        let first = BrainEntryRequest.next(focus: "N1", afterToken: 0)
        let second = BrainEntryRequest.next(focus: "N1", afterToken: first.token)
        #expect(first.token == 1)
        #expect(second.token == 2)
        #expect(second != first, "the same focus twice is two requests")
        #expect(BrainEntryRequest.next(focus: nil, afterToken: 7).token == 8)
    }

    @Test func aFreshRequestIsAppliedAtTheDefaultDepth() throws {
        let entry = BrainEntryRequest.memory(Self.memory, afterToken: 0)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: nil))
        #expect(applied.focus == "0A1B2C3D-0000-4000-8000-00000000ABCD")
        #expect(applied.depth == 1)
        #expect(applied.token == entry.token)
    }

    @Test func aRequestIsAppliedOnce() throws {
        let entry = BrainEntryRequest.memory(Self.memory, afterToken: 0)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: nil))
        #expect(BrainEntryRequest.apply(entry, lastApplied: applied.token) == nil)
        #expect(BrainEntryRequest.apply(nil, lastApplied: nil) == nil)
    }

    @Test func aNewRequestReplacesTheFocusAlreadySet() throws {
        let first = BrainEntryRequest.memory(Self.memory, afterToken: 0)
        let second = BrainEntryRequest.next(focus: "N7", afterToken: first.token)
        let applied = try #require(BrainEntryRequest.apply(second, lastApplied: first.token))
        #expect(applied.focus == "N7")
    }

    @Test func anEntryWithNoFocusMeansTheFullGraph() throws {
        let entry = BrainEntryRequest(focus: nil, token: 3)
        let applied = try #require(BrainEntryRequest.apply(entry, lastApplied: 2))
        #expect(applied.focus == nil)
        #expect(applied.depth == 1)
    }

    // MARK: acknowledging

    @Test func theAppliedRequestIsClearedAndANewerOneIsKept() {
        let one = BrainEntryRequest(focus: "N1", token: 1)
        let two = BrainEntryRequest(focus: "N2", token: 2)
        #expect(BrainEntryRequest.acknowledge(one, applied: 1) == nil)
        #expect(BrainEntryRequest.acknowledge(two, applied: 1) == two)
        #expect(BrainEntryRequest.acknowledge(nil, applied: 1) == nil)
        #expect(BrainEntryRequest.acknowledge(one, applied: nil) == one)
    }

    // MARK: vault filter

    @Test func anEntryWithAFocusClearsTheVaultFilter() throws {
        let filtered: Set<UUID> = [UUID()]
        let applied = try #require(BrainEntryRequest.apply(.init(focus: "N6", token: 1), lastApplied: nil))
        #expect(applied.vaults(keeping: filtered) == nil)
    }

    @Test func anEntryWithoutAFocusLeavesTheVaultFilterAlone() throws {
        let filtered: Set<UUID> = [UUID()]
        let applied = try #require(BrainEntryRequest.apply(.init(focus: nil, token: 1), lastApplied: nil))
        #expect(applied.vaults(keeping: filtered) == filtered)
        #expect(applied.vaults(keeping: nil) == nil)
    }

    // MARK: whether the request changes

    @Test func theSameFocusAtTheSameDepthAndVaultsChangesNothing() throws {
        let applied = try #require(BrainEntryRequest.apply(.init(focus: "N3", token: 2), lastApplied: nil))
        #expect(applied.changesRequest(focus: "N3", depth: 1, vaults: nil) == false)
    }

    @Test func aDeeperCurrentDepthOrANarrowedVaultSetChangesTheRequest() throws {
        let applied = try #require(BrainEntryRequest.apply(.init(focus: "N3", token: 2), lastApplied: nil))
        #expect(applied.changesRequest(focus: "N3", depth: 3, vaults: nil))
        #expect(applied.changesRequest(focus: "N3", depth: 1, vaults: [UUID()]))
        #expect(applied.changesRequest(focus: "N4", depth: 1, vaults: nil))
        #expect(applied.changesRequest(focus: nil, depth: 1, vaults: nil))
    }

    @Test func theFullGraphEntryChangesNothingWhenAlreadyOnTheFullGraph() throws {
        let applied = try #require(BrainEntryRequest.apply(.init(focus: nil, token: 2), lastApplied: nil))
        #expect(applied.changesRequest(focus: nil, depth: 1, vaults: nil) == false)
        #expect(applied.changesRequest(focus: "N1", depth: 1, vaults: nil))
        #expect(applied.changesRequest(focus: nil, depth: 1, vaults: [UUID()]) == false,
                "an entry without a focus leaves the filter, so it asks for nothing new")
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
        let old = UUID(), new = UUID()
        let (a1, b1, a2, b2) = (UUID(), UUID(), UUID(), UUID())
        let a = BrainGraphNodeDTO(
            id: "entity:a", kind: .entity, label: "a", weight: 1,
            refs: [BrainGraphRefDTO(vaultID: old, id: a1), BrainGraphRefDTO(vaultID: new, id: a2)]
        )
        let b = BrainGraphNodeDTO(
            id: "entity:b", kind: .entity, label: "b", weight: 1,
            refs: [BrainGraphRefDTO(vaultID: old, id: b1), BrainGraphRefDTO(vaultID: new, id: b2)]
        )
        var tracker = BrainActiveVaultTracker()
        _ = tracker.observe(old)
        #expect(BrainTrayActions.explainTarget(a, b, activeVault: tracker.current) == BrainExplainTarget(from: a1, to: b1))
        let changed = tracker.observe(new)
        #expect(changed)
        #expect(BrainTrayActions.explainTarget(a, b, activeVault: tracker.current) == BrainExplainTarget(from: a2, to: b2))
    }
}
