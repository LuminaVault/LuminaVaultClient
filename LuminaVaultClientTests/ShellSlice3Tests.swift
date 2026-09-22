// LuminaVaultClient/LuminaVaultClientTests/ShellSlice3Tests.swift
//
// Palette ranking (shared with the web client) and the run registry behind
// the "agent working" banner.

import XCTest
@testable import LuminaVaultClient

final class CommandPaletteMatcherTests: XCTestCase {
    private typealias Entry = CommandPaletteMatcher.Entry

    func testMatchesInOrderNotContiguously() {
        XCTAssertTrue(CommandPaletteMatcher.subsequenceMatch("Insights", "ins"))
        XCTAssertTrue(CommandPaletteMatcher.subsequenceMatch("Settings", "stg"))
        XCTAssertFalse(CommandPaletteMatcher.subsequenceMatch("Settings", "gts"))
        XCTAssertTrue(CommandPaletteMatcher.subsequenceMatch("Chat preferences", " CHAT PREF "))
        XCTAssertTrue(CommandPaletteMatcher.subsequenceMatch("anything", ""))
    }

    /// Typing "chat" must offer Chat above Chat preferences.
    func testTheObviousAnswerComesFirst() {
        let entries = [Entry(id: "b", label: "Chat preferences", group: "Settings"), Entry(id: "a", label: "Chat", group: "Work")]
        XCTAssertEqual(CommandPaletteMatcher.filter(entries, "chat").map(\.label), ["Chat", "Chat preferences"])
    }

    func testTiesAreAlphabeticalSoTheListDoesNotReshuffle() {
        let entries = [Entry(id: "b", label: "Beta", group: "x"), Entry(id: "a", label: "Alpha", group: "x")]
        XCTAssertEqual(CommandPaletteMatcher.filter(entries, "a").map(\.label), ["Alpha", "Beta"])
    }

    func testKeywordsMatchWithoutBeingShown() {
        let entries = [Entry(id: "s", label: "Settings", group: "App", keywords: ["theme"])]
        XCTAssertEqual(CommandPaletteMatcher.filter(entries, "theme").count, 1)
        XCTAssertTrue(CommandPaletteMatcher.filter(entries, "zzzz").isEmpty)
    }

    /// Every palette entry must resolve to something, or Return does nothing.
    func testEveryShellEntryIsRunnable() {
        for entry in MainTabView.paletteEntries where entry.id != "settings" {
            let raw = entry.id.replacingOccurrences(of: "tab.", with: "")
            XCTAssertNotNil(MainTabView.AppTab(rawValue: raw), entry.id)
        }
        XCTAssertEqual(Set(MainTabView.paletteEntries.map(\.id)).count, MainTabView.paletteEntries.count)
    }
}

@MainActor
final class ShellActivityTests: XCTestCase {
    func testAReconnectingRunCountsOnce() async {
        let activity = ShellActivity()
        let run = UUID()
        activity.begin(run)
        activity.begin(run)
        XCTAssertEqual(activity.runIDs.count, 1)
    }

    func testEndingTheLastRunGoesQuiet() async {
        let activity = ShellActivity()
        let run = UUID()
        activity.begin(run)
        activity.begin(UUID())
        activity.end(run)
        XCTAssertTrue(activity.busy)
        activity.clear()
        XCTAssertFalse(activity.busy)
    }
}
