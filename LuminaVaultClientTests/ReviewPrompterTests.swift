// LuminaVaultClient/LuminaVaultClientTests/ReviewPrompterTests.swift
//
// Rating-prompt rules: 3rd success moment, never in the first 24 h, at most
// once per 120 days, never when opted out, and reset after a prompt.

import XCTest
@testable import LuminaVaultClient

/// Test clock + isolated defaults.
///
/// Every test method is `async` on purpose: this toolchain aborts
/// (`malloc: pointer being freed was not allocated`) on a *synchronous* test
/// method in a `@MainActor` XCTestCase, repo-wide (see HomeGlanceViewModelTests).
@MainActor
private final class Fixture {
    let suiteName = "ReviewPrompterTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() { defaults = UserDefaults(suiteName: suiteName)! }

    func makePrompter() -> ReviewPrompter {
        ReviewPrompter(defaults: defaults, now: { [unowned self] in self.clock })
    }

    func advance(_ interval: TimeInterval) { clock = clock.addingTimeInterval(interval) }

    func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }
}

@MainActor
final class ReviewPrompterTests: XCTestCase {
    private static let day: TimeInterval = 24 * 60 * 60

    private func withFixture(_ body: (Fixture) -> Void) {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        body(fixture)
    }

    private func recordSuccesses(_ n: Int, on prompter: ReviewPrompter) {
        for _ in 0..<n { prompter.recordSuccess() }
    }

    // MARK: - Threshold

    func testRecordsFirstSeenOnInit() async {
        withFixture { f in
            let prompter = f.makePrompter()
            XCTAssertEqual(prompter.firstSeenAt, f.clock)
        }
    }

    func testDoesNotRewriteFirstSeen() async {
        withFixture { f in
            _ = f.makePrompter()
            let first = f.clock
            f.advance(5 * Self.day)
            let prompter = f.makePrompter()
            XCTAssertEqual(prompter.firstSeenAt, first)
        }
    }

    func testPromptDueOnlyAtThirdSuccess() async {
        withFixture { f in
            let prompter = f.makePrompter()
            f.advance(2 * Self.day)

            self.recordSuccesses(2, on: prompter)
            XCTAssertFalse(prompter.hasPendingPrompt)

            prompter.recordSuccess()
            XCTAssertTrue(prompter.hasPendingPrompt)
            XCTAssertTrue(prompter.consumePendingPrompt())
        }
    }

    // MARK: - First session

    func testNeverPromptsWithin24HoursOfFirstSeen() async {
        withFixture { f in
            let prompter = f.makePrompter()
            f.advance(23 * 60 * 60)
            self.recordSuccesses(5, on: prompter)
            XCTAssertFalse(prompter.hasPendingPrompt)
            XCTAssertFalse(prompter.consumePendingPrompt())

            // Once 24 h have passed, the next success makes it due.
            f.advance(60 * 60)
            prompter.recordSuccess()
            XCTAssertTrue(prompter.hasPendingPrompt)
        }
    }

    // MARK: - Reset

    func testPromptResetsCountAndRecordsLastPrompt() async {
        withFixture { f in
            let prompter = f.makePrompter()
            f.advance(2 * Self.day)
            self.recordSuccesses(3, on: prompter)

            XCTAssertTrue(prompter.consumePendingPrompt())
            XCTAssertEqual(prompter.successCount, 0)
            XCTAssertEqual(prompter.lastPromptAt, f.clock)
            XCTAssertFalse(prompter.hasPendingPrompt)
            // A consumed prompt can't be consumed twice.
            XCTAssertFalse(prompter.consumePendingPrompt())
        }
    }

    // MARK: - Cooldown

    func testCooldownBlocksPromptFor120Days() async {
        withFixture { f in
            let prompter = f.makePrompter()
            f.advance(2 * Self.day)
            self.recordSuccesses(3, on: prompter)
            XCTAssertTrue(prompter.consumePendingPrompt())

            f.advance(119 * Self.day)
            self.recordSuccesses(3, on: prompter)
            XCTAssertFalse(prompter.hasPendingPrompt)

            f.advance(1 * Self.day)
            prompter.recordSuccess()
            XCTAssertTrue(prompter.hasPendingPrompt)
            XCTAssertTrue(prompter.consumePendingPrompt())
        }
    }

    func testPurchasePromptCountsTowardCooldown() async {
        withFixture { f in
            let prompter = f.makePrompter()
            XCTAssertTrue(prompter.consumePurchasePrompt())
            XCTAssertEqual(prompter.lastPromptAt, f.clock)
            XCTAssertFalse(prompter.consumePurchasePrompt())

            f.advance(2 * Self.day)
            self.recordSuccesses(3, on: prompter)
            XCTAssertFalse(prompter.hasPendingPrompt)
        }
    }

    // MARK: - Opt-out

    func testOptOutBlocksSuccessPrompt() async {
        withFixture { f in
            let prompter = f.makePrompter()
            prompter.promptsEnabled = false
            f.advance(2 * Self.day)
            self.recordSuccesses(3, on: prompter)
            XCTAssertFalse(prompter.hasPendingPrompt)
        }
    }

    func testOptOutAfterDueCancelsPendingPrompt() async {
        withFixture { f in
            let prompter = f.makePrompter()
            f.advance(2 * Self.day)
            self.recordSuccesses(3, on: prompter)
            XCTAssertTrue(prompter.hasPendingPrompt)

            prompter.promptsEnabled = false
            XCTAssertFalse(prompter.consumePendingPrompt())
            XCTAssertNil(prompter.lastPromptAt)
        }
    }

    func testOptOutBlocksPurchasePrompt() async {
        withFixture { f in
            let prompter = f.makePrompter()
            prompter.promptsEnabled = false
            XCTAssertFalse(prompter.consumePurchasePrompt())
            XCTAssertNil(prompter.lastPromptAt)
        }
    }

    func testPromptsEnabledDefaultsOnAndPersistsUnderKey() async {
        withFixture { f in
            let prompter = f.makePrompter()
            XCTAssertTrue(prompter.promptsEnabled)
            f.defaults.set(false, forKey: ReviewPrompter.Keys.promptsEnabled)
            XCTAssertFalse(prompter.promptsEnabled)
            XCTAssertEqual(ReviewPrompter.Keys.promptsEnabled, "lv.review.promptsEnabled")
        }
    }
}
