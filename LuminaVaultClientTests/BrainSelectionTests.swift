// Port of the web app's selection.test.ts. Hover has no touch equivalent, so the
// setHover cases and the hover halves of the prune and highlight cases are skipped.

import Foundation
import Synchronization
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
struct BrainSelectionTests {
    private static let vault = UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))

    private static let graph = BrainGraphResponse(
        generatedAt: Date(timeIntervalSince1970: 0),
        vaults: [BrainGraphVaultDTO(id: vault, name: "Personal", personal: true)],
        nodes: ["a", "b", "c", "d"].map {
            BrainGraphNodeDTO(id: $0, kind: .note, label: $0, vaultID: vault, weight: 0)
        },
        edges: [
            BrainGraphEdgeDTO(from: "a", to: "b", kind: .link),
            BrainGraphEdgeDTO(from: "b", to: "c", kind: .link),
        ]
    )
    private static let index = BrainGraphModel
        .visible(graph, filters: BrainGraphModel.defaultFilters()).index

    // MARK: click

    @Test func selectsOnlyAnUnselectedPointOnAPlainClick() {
        let s = BrainSelection()
        s.click("a", additive: false)
        s.click("b", additive: false)
        #expect(s.selected == ["b"])
    }

    @Test func clearsWhenTheOnlySelectedPointIsClickedPlainly() {
        let s = BrainSelection()
        s.click("a", additive: false)
        s.click("a", additive: false)
        #expect(s.selected == [])
    }

    @Test func selectsOnlyTheClickedPointWhenItIsOneOfSeveral() {
        let s = BrainSelection()
        s.click("a", additive: true)
        s.click("b", additive: true)
        s.click("a", additive: false)
        #expect(s.selected == ["a"])
    }

    @Test func togglesOnAnAdditiveClickAndLeavesTheRest() {
        let s = BrainSelection()
        for id in ["a", "b", "c", "b"] { s.click(id, additive: true) }
        #expect(s.selected == ["a", "c"])
    }

    // Web "reassigns the array on every change" is about reference identity for
    // Svelte reactivity; arrays are values here and @Observable tracks the property.
    // The behaviour that matters is that every change is observable.
    @Test func everyChangeIsObservable() {
        let s = BrainSelection()
        let changes = Mutex(0)
        withObservationTracking { _ = s.selected } onChange: { changes.withLock { $0 += 1 } }
        s.click("a", additive: true)
        #expect(changes.withLock { $0 } == 1)
        #expect(s.selected == ["a"])
    }

    // MARK: selectGroup

    @Test func selectGroupReplacesTheSelectionInOrderWithoutDuplicates() {
        let s = BrainSelection()
        s.click("d", additive: false)
        s.selectGroup(["a", "b", "a"], additive: false)
        #expect(s.selected == ["a", "b"])
    }

    @Test func selectGroupUnionsWhenAdditiveKeepingTheOrderPicked() {
        let s = BrainSelection()
        s.click("b", additive: false)
        s.selectGroup(["a", "b", "c"], additive: true)
        #expect(s.selected == ["b", "a", "c"])
    }

    // MARK: remove, clear

    @Test func removesASelectedID() {
        let s = BrainSelection()
        s.selectGroup(["a", "b"], additive: false)
        s.remove("a")
        #expect(s.selected == ["b"])
    }

    @Test func removeIsANoOpForAnIDThatIsNotSelected() {
        let s = BrainSelection()
        s.selectGroup(["a"], additive: false)
        s.remove("z")
        #expect(s.selected == ["a"])
    }

    @Test func clearEmptiesTheSelection() {
        let s = BrainSelection()
        s.selectGroup(["a", "b"], additive: false)
        s.clear()
        #expect(s.selected == [])
    }

    // MARK: prune

    @Test func pruneDropsHiddenIDsAndKeepsTheOrderOfTheRest() {
        let s = BrainSelection()
        s.selectGroup(["c", "a", "b"], additive: false)
        s.prune(visible: ["c", "b"])
        #expect(s.selected == ["c", "b"])
    }

    @Test func pruneLeavesTheSelectionAloneWhenNothingIsHidden() {
        let s = BrainSelection()
        s.selectGroup(["a", "b"], additive: false)
        s.prune(visible: ["a", "b", "c"])
        #expect(s.selected == ["a", "b"])
    }

    // MARK: highlight

    @Test func highlightHasLitNilWhenNothingIsSelected() {
        let h = BrainSelection().highlight(index: Self.index)
        #expect(h.lit == nil)
        #expect(h.selected.isEmpty)
    }

    @Test func highlightLightsTheSelectionAndItsNeighbours() {
        let s = BrainSelection()
        s.click("a", additive: false)
        let h = s.highlight(index: Self.index)
        #expect(h.selected == ["a"])
        #expect(h.lit == ["a", "b"])
    }
}
