// Port of the web app's tray-actions.test.ts. runTrayAction returns an outcome
// value instead of calling a context, so its cases assert on the outcomes.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

struct BrainTrayActionsTests {
    private static let vault = UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0, 0, 0, 0, 0, 1))
    private static let otherVault = UUID(uuid: (0xBB, 0xBB, 0xBB, 0xBB, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0, 0, 0, 0, 0, 2))
    private static func ref(_ n: UInt8) -> UUID { UUID(uuid: (0xDD, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n)) }

    private static func item(_ n: Int) -> String {
        "CCCCCCCC-0000-4000-8000-\(String(format: "%012d", n))"
    }

    private static func note(_ n: Int, _ kind: BrainNodeKindDTO = .note, label: String? = nil) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: item(n), kind: kind, label: label ?? "Item \(n)", vaultID: vault, weight: 1)
    }

    private static func entity(_ key: String, _ refs: [BrainGraphRefDTO]?) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: "entity:\(key)", kind: .entity, label: key, weight: 2, refs: refs)
    }

    private static let tag = BrainGraphNodeDTO(id: "tag:migration", kind: .tag, label: "migration", weight: 3)

    private static let graph = BrainGraphResponse(
        generatedAt: Date(timeIntervalSince1970: 0),
        vaults: [BrainGraphVaultDTO(id: vault, name: "Personal", personal: true)],
        nodes: [note(1), note(2, .memory), note(3), tag],
        edges: [
            BrainGraphEdgeDTO(from: item(1), to: "tag:migration", kind: .tag),
            BrainGraphEdgeDTO(from: item(2), to: "tag:migration", kind: .tag),
            BrainGraphEdgeDTO(from: item(3), to: "tag:migration", kind: .tag),
            BrainGraphEdgeDTO(from: item(1), to: item(2), kind: .link),
        ]
    )
    private static let visible = BrainGraphModel.visible(graph, filters: BrainGraphModel.defaultFilters())

    private func action(_ nodes: [BrainGraphNodeDTO], _ id: BrainTrayActionID) throws -> BrainTrayAction {
        try #require(BrainTrayActions.actions(for: nodes, index: Self.visible.index).first { $0.id == id })
    }

    private func run(_ id: BrainTrayActionID, _ nodes: [BrainGraphNodeDTO], activeVault: UUID? = BrainTrayActionsTests.vault)
        -> BrainTrayOutcome?
    {
        BrainTrayActions.run(id, nodes: nodes, index: Self.visible.index, activeVault: activeVault)
    }

    // MARK: actions

    @Test func alwaysListsTheSameFiveActionsInTheSameOrder() {
        let (n1, n2, n3) = (Self.note(1), Self.note(2), Self.note(3))
        for nodes in [[n1], [n1, n2], [Self.tag], [n1, n2, n3]] {
            #expect(BrainTrayActions.actions(for: nodes, index: Self.visible.index).map(\.label)
                == ["Open", "Focus", "Select group", "Explain connection", "Ask"])
        }
    }

    @Test func enablesOpenForExactlyOneNoteOrMemoryNeverForAHub() throws {
        #expect(try action([Self.note(1)], .open).isEnabled)
        #expect(try action([Self.note(2, .memory)], .open).isEnabled)
        #expect(try !action([Self.tag], .open).isEnabled)
        #expect(try !action([Self.note(1), Self.note(2)], .open).isEnabled)
    }

    @Test func enablesFocusForExactlyOnePointOfAnyKind() throws {
        #expect(try action([Self.note(1)], .focus).isEnabled)
        #expect(try action([Self.tag], .focus).isEnabled)
        #expect(try !action([Self.note(1), Self.tag], .focus).isEnabled)
    }

    @Test func enablesSelectGroupForExactlyOneHub() throws {
        #expect(try action([Self.tag], .group).isEnabled)
        #expect(try !action([Self.note(1)], .group).isEnabled)
        #expect(try !action([Self.tag, Self.note(1)], .group).isEnabled)
    }

    @Test func disablesSelectGroupWhenNoneOfTheHubsMembersAreShowing() throws {
        let bare = BrainGraphIndex(byID: [Self.tag.id: Self.tag])
        let group = try #require(BrainTrayActions.actions(for: [Self.tag], index: bare).first { $0.id == .group })
        #expect(!group.isEnabled)
        #expect(group.reason == "No notes in this group are showing")
        let none = try #require(BrainTrayActions.actions(for: [Self.tag], index: nil).first { $0.id == .group })
        #expect(!none.isEnabled)
    }

    @Test func enablesExplainConnectionForExactlyTwo() throws {
        #expect(try !action([Self.note(1)], .explain).isEnabled)
        #expect(try action([Self.note(1), Self.tag], .explain).isEnabled)
        #expect(try !action([Self.note(1), Self.note(2), Self.note(3)], .explain).isEnabled)
    }

    @Test func enablesAskForAnySelection() throws {
        #expect(try action([Self.note(1)], .ask).isEnabled)
        #expect(try action([Self.note(1), Self.note(2), Self.note(3), Self.tag], .ask).isEnabled)
    }

    @Test func givesEveryDisabledActionAReasonAndNoEnabledOne() throws {
        let selections = [
            [Self.note(1)], [Self.tag], [Self.note(1), Self.note(2)],
            [Self.note(1), Self.note(2), Self.note(3)],
        ]
        for nodes in selections {
            for a in BrainTrayActions.actions(for: nodes, index: Self.visible.index) {
                if a.isEnabled {
                    #expect(a.reason == nil)
                } else {
                    #expect(a.reason?.contains(where: \.isLetter) == true)
                }
            }
        }
        #expect(try action([Self.note(1)], .explain).reason == "Select exactly two to explain a connection")
    }

    @Test func disabledReasonsMatchTheWebStrings() throws {
        #expect(try action([], .open).reason == "Select one note or memory to open it")
        #expect(try action([Self.tag], .open).reason == "A group cannot be opened; use Select group")
        #expect(try action([], .focus).reason == "Select exactly one to focus on it")
        #expect(try action([Self.note(1)], .group).reason
            == "Select one tag, author, mention or Space to select its group")
        #expect(try action([], .ask).reason == "Select something to ask about it")
    }

    // MARK: run

    @Test func doesNothingForADisabledAction() {
        #expect(run(.open, [Self.tag]) == nil)
        #expect(run(.explain, [Self.note(1)]) == nil)
    }

    @Test func opensOneNoteFocusesOnePointAndSelectsAHubsGroup() throws {
        #expect(run(.open, [Self.note(2, .memory)]) == .open(Self.note(2, .memory)))
        #expect(run(.focus, [Self.tag]) == .focus("tag:migration"))
        let outcome = try #require(run(.group, [Self.tag]))
        guard case let .select(ids) = outcome else { Issue.record("expected select"); return }
        #expect(ids.sorted() == [Self.item(1), Self.item(2), Self.item(3)].sorted())
    }

    @Test func explainsTwoEntityHubsByTheirRefsInTheActiveVault() {
        let a = Self.entity("hermes", [BrainGraphRefDTO(vaultID: Self.vault, id: Self.ref(1))])
        let b = Self.entity("cloudflare", [BrainGraphRefDTO(vaultID: Self.vault, id: Self.ref(2))])
        #expect(run(.explain, [a, b]) == .explain(from: Self.ref(1), to: Self.ref(2)))
    }

    @Test func asksASentQuestionForTwoPointsItCannotExplainDirectly() {
        let outcome = run(.explain, [Self.note(1, label: "Alpha"), Self.note(3, label: "Beta")])
        #expect(outcome == .ask(query: "How are \"Alpha\" and \"Beta\" connected?", send: true))
    }

    @Test func prefillsAskWithoutSendingIt() {
        let outcome = run(.ask, [Self.note(1, label: "Alpha"), Self.tag])
        #expect(outcome == .ask(query: "What connects Alpha, migration?", send: false))
    }

    // MARK: explainTarget

    private static let a = entity("hermes", [
        BrainGraphRefDTO(vaultID: otherVault, id: ref(10)),
        BrainGraphRefDTO(vaultID: vault, id: ref(11)),
    ])
    private static let b = entity("cloudflare", [BrainGraphRefDTO(vaultID: vault, id: ref(12))])

    @Test func explainTargetReturnsBothRefsInTheActiveVault() {
        #expect(BrainTrayActions.explainTarget(Self.a, Self.b, activeVault: Self.vault)
            == BrainExplainTarget(from: Self.ref(11), to: Self.ref(12)))
    }

    // Web compares vault ids case-insensitively; here they are UUID values, so the
    // equivalent is a UUID parsed from lowercase text.
    @Test func explainTargetMatchesAVaultParsedFromEitherCase() throws {
        let lower = try #require(UUID(uuidString: Self.vault.uuidString.lowercased()))
        #expect(BrainTrayActions.explainTarget(Self.a, Self.b, activeVault: lower)
            == BrainExplainTarget(from: Self.ref(11), to: Self.ref(12)))
    }

    @Test func explainTargetIsNilWhenTheActiveVaultIsNil() {
        #expect(BrainTrayActions.explainTarget(Self.a, Self.b, activeVault: nil) == nil)
    }

    @Test func explainTargetIsNilWhenEitherHasNoRefInTheActiveVault() {
        let elsewhere = Self.entity("elsewhere", [BrainGraphRefDTO(vaultID: Self.otherVault, id: Self.ref(13))])
        #expect(BrainTrayActions.explainTarget(Self.a, elsewhere, activeVault: Self.vault) == nil)
        #expect(BrainTrayActions.explainTarget(Self.entity("bare", nil), Self.b, activeVault: Self.vault) == nil)
    }

    @Test func explainTargetIsNilUnlessBothAreEntityHubs() {
        let withRefs = BrainGraphNodeDTO(
            id: Self.tag.id, kind: .tag, label: "migration", weight: 3,
            refs: [BrainGraphRefDTO(vaultID: Self.vault, id: Self.ref(14))]
        )
        #expect(BrainTrayActions.explainTarget(withRefs, Self.b, activeVault: Self.vault) == nil)
        #expect(BrainTrayActions.explainTarget(Self.note(1), Self.b, activeVault: Self.vault) == nil)
    }

    // MARK: copy

    @Test func truncatesChipLabelsToTwentyFourCharacters() {
        #expect(BrainTrayActions.chipLabel("Short") == "Short")
        #expect(BrainTrayActions.chipLabel(String(repeating: "x", count: 24)) == String(repeating: "x", count: 24))
        let long = BrainTrayActions.chipLabel("A label that is much longer than the chip")
        #expect(long.count == 24)
        #expect(long.hasSuffix("…"))
    }

    @Test func buildsThePrefilledQuestions() {
        #expect(BrainTrayActions.askQuery(["A", "B", "C"]) == "What connects A, B, C?")
        #expect(BrainTrayActions.explainQuery("A", "B") == "How are \"A\" and \"B\" connected?")
    }

    @Test func namesTheFirstFiveInAPrefilledQuestionThenHowManyMore() {
        let labels = ["A", "B", "C", "D", "E", "F", "G", "H"]
        #expect(BrainTrayActions.askQuery(Array(labels.prefix(5))) == "What connects A, B, C, D, E?")
        #expect(BrainTrayActions.askQuery(Array(labels.prefix(6))) == "What connects A, B, C, D, E and 1 more?")
        #expect(BrainTrayActions.askQuery(labels) == "What connects A, B, C, D, E and 3 more?")
    }

    // MARK: withReasoning

    @Test func addsNamedMemoriesOnScreenUppercasedWithoutTheirNeighbours() {
        let base = BrainHighlight(selected: [Self.item(3)], lit: [Self.item(3), "tag:migration"])
        let out = BrainTrayActions.withReasoning(
            base, memoryIDs: [Self.item(2).lowercased(), "not-on-screen"], index: Self.visible.index
        )
        #expect(out.lit == [Self.item(3), "tag:migration", Self.item(2)])
        #expect(out.selected == base.selected)
    }

    @Test func lightsOnlyTheNamedMemoriesWhenNothingIsSelected() {
        let out = BrainTrayActions.withReasoning(
            BrainHighlight(selected: [], lit: nil), memoryIDs: [Self.item(2)], index: Self.visible.index
        )
        #expect(out.lit == [Self.item(2)])
    }

    @Test func leavesTheHighlightAloneWhenNoNamedMemoryIsOnScreen() {
        let base = BrainHighlight(selected: [], lit: nil)
        #expect(BrainTrayActions.withReasoning(base, memoryIDs: ["missing"], index: Self.visible.index) == base)
        #expect(BrainTrayActions.withReasoning(base, memoryIDs: [], index: Self.visible.index) == base)
    }

    // MARK: screen rules (iOS only)

    @Test func withoutAReasoningClientExplainAndAskSayWhyNot() throws {
        let nodes = [Self.note(1), Self.note(2)]
        let actions = BrainTrayActions.actions(for: nodes, index: Self.visible.index, reasoningAvailable: false)
        let byID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        #expect(byID[.explain]?.reason == BrainTrayActions.reasoningUnavailable)
        #expect(byID[.ask]?.reason == BrainTrayActions.reasoningUnavailable)
        // The rest are as the web rules have them.
        #expect(byID[.open] == BrainTrayActions.actions(for: nodes, index: Self.visible.index).first { $0.id == .open })
        #expect(BrainTrayActions.run(
            .ask, nodes: nodes, index: Self.visible.index, activeVault: Self.vault, reasoningAvailable: false
        ) == nil)
        #expect(BrainTrayActions.run(
            .explain, nodes: nodes, index: Self.visible.index, activeVault: Self.vault, reasoningAvailable: false
        ) == nil)
    }

    @Test func anExplanationIsAboutBothLabelsInOrder() {
        #expect(BrainTrayActions.explainSubject([Self.note(1), Self.note(2)]) == "Item 1 and Item 2")
        #expect(BrainTrayActions.explainSubject([Self.note(1)]) == nil)
        #expect(BrainTrayActions.explainSubject([Self.note(1), Self.note(2), Self.note(3)]) == nil)
    }

    /// A double tap runs Open on the point alone: an item opens, a group does not.
    @Test func openingOnePointOpensItemsNotGroups() {
        #expect(run(.open, [Self.note(2, .memory)]) == .open(Self.note(2, .memory)))
        #expect(run(.open, [Self.tag]) == nil)
    }
}
