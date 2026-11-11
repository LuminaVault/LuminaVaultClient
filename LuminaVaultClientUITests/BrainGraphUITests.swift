// The Brain screen against a stubbed graph client. The app starts straight on
// the screen when launched with `-BrainUITestScenario <name>` (DEBUG builds
// only; see `BrainUITestHarness`), and shows how many graph requests the stub
// has answered in an element named `brain.uitest.requests`.

import XCTest

nonisolated final class BrainGraphUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: helpers

    @MainActor
    private func launch(_ scenario: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-BrainUITestScenario", scenario] + extra
        app.launch()
        return app
    }

    @MainActor
    private func requests(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["brain.uitest.requests"]
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "label == %@", label)
        let found = expectation(for: predicate, evaluatedWith: element)
        wait(for: [found], timeout: timeout)
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "value == %@", value)
        let found = expectation(for: predicate, evaluatedWith: element)
        wait(for: [found], timeout: timeout)
    }

    /// Longer than the store's 400 ms debounce, so a request that was going to
    /// be sent has been.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func counts(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["brain.status.counts"]
    }

    @MainActor
    private func canvas(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["brain.canvas"]
    }

    @MainActor
    private func openFilters(_ app: XCUIApplication) {
        app.buttons["brain.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
    }

    /// Scrolls the sheet's form until `element` is on screen.
    @MainActor
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) -> XCUIElement {
        var tries = 0
        while !(element.exists && element.isHittable), tries < 4 {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            tries += 1
        }
        return element
    }

    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["brain.sheet.done"].tap()
    }

    @MainActor
    private func search(_ app: XCUIApplication, _ text: String, pick label: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        let suggestion = app.buttons["brain.search.\(label)"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: graph

    @MainActor
    func testCountsLine() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        waitForLabel(requests(app), "requests: 1")
    }

    @MainActor
    func testFilterToggleChangesCountsAndMakesNoRequest() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        reveal(app, app.switches["brain.filter.link.tag"]).switches.firstMatch.tap()
        closeSheet(app)
        waitForLabel(counts(app), "8 notes and memories · 4 connections")
        settle()
        waitForLabel(requests(app), "requests: 1")
        XCTAssertTrue(app.buttons["brain.filters"].label.contains("1"), "badge counts one change")
    }

    @MainActor
    func testVaultChipMakesExactlyOneRequest() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        app.buttons["brain.filter.vault.Work"].tap()
        settle()
        closeSheet(app)
        waitForLabel(requests(app), "requests: 2")
        waitForLabel(counts(app), "5 notes and memories · 6 connections")
        settle()
        waitForLabel(requests(app), "requests: 2")
    }

    @MainActor
    func testSearchSelectsAPoint() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas(app), "Selected: Garden plans")
        waitForLabel(requests(app), "requests: 1")
    }

    @MainActor
    func testListRowSelectionIsShown() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        let row = app.buttons["brain.list.row.N3"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(row.isSelected)
        row.tap()
        XCTAssertTrue(row.isSelected)
        closeSheet(app)
        waitForValue(canvas(app), "Selected: Sleep log")
        waitForLabel(requests(app), "requests: 1")
    }

    // MARK: states

    @MainActor
    func testEmptyStateOffersCapture() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["Nothing to map yet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["brain.empty.capture"].exists)
        XCTAssertFalse(canvas(app).exists)
    }

    @MainActor
    func testFailedStateOffersRetry() {
        let app = launch("failed")
        let retry = app.buttons["brain.failed.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Show all vaults"].exists)
        waitForLabel(requests(app), "requests: 1")
        retry.tap()
        waitForLabel(requests(app), "requests: 2")
    }

    @MainActor
    func testMissingFocusShowsTheFullGraph() {
        let app = launch("missingFocus")
        XCTAssertTrue(
            app.staticTexts["That is no longer in your graph. It may have been deleted."].waitForExistence(timeout: 8)
        )
        app.buttons["Show full graph"].tap()
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        waitForLabel(requests(app), "requests: 2")
    }

    @MainActor
    func testARateLimitKeepsTheGraphWithOneNotice() {
        let app = launch("stale")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        app.buttons["brain.filter.vault.Work"].tap()
        closeSheet(app)
        XCTAssertTrue(app.staticTexts["Showing an earlier graph"].waitForExistence(timeout: 8))
        // The earlier graph stays, filtered in place to the vaults now chosen.
        XCTAssertTrue(canvas(app).exists)
        waitForLabel(counts(app), "5 notes and memories · 6 connections")
        settle()
        waitForLabel(requests(app), "requests: 2")
        XCTAssertEqual(app.buttons.matching(identifier: "brain.status.retry").count, 1)
        attach(app, "stale")
    }

    @MainActor
    func testRefreshingKeepsTheGraph() {
        let app = launch("refreshing")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        app.buttons["brain.filter.vault.Work"].tap()
        closeSheet(app)
        waitForLabel(requests(app), "requests: 2")
        XCTAssertTrue(app.descendants(matching: .any)["brain.status.refreshing"].waitForExistence(timeout: 5))
        XCTAssertTrue(canvas(app).exists)
        attach(app, "refreshing")
    }

    // MARK: gestures

    /// Search puts a point in the middle of the canvas; everything else is
    /// driven from there. Selection shows in the canvas's accessibility value.
    @MainActor
    func testCanvasGestures() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        let canvas = canvas(app)
        let centre = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let corner = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04))

        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas, "Selected: Garden plans")
        settle()
        attach(app, "centred on Garden plans")

        // Tap the only selected point: it toggles off. Tap again: back on.
        centre.tap()
        waitForValue(canvas, "Nothing selected")
        centre.tap()
        waitForValue(canvas, "Selected: Garden plans")

        // Tap the background: clears.
        corner.tap()
        waitForValue(canvas, "Nothing selected")

        // Long press adds to the selection without replacing it.
        centre.tap()
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        app.buttons["brain.list.row.N3"].tap()
        closeSheet(app)
        waitForValue(canvas, "2 selected")
        centre.press(forDuration: 0.9)
        waitForValue(canvas, "Selected: Sleep log")
        centre.press(forDuration: 0.9)
        waitForValue(canvas, "2 selected")

        // Two selected from here on, so a tap that hits Garden plans reads
        // "Selected: Garden plans" and one that misses reads "Nothing selected".

        // Drag on the background pans the view: the middle is empty now.
        corner.press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
        settle()
        attach(app, "after panning")
        centre.tap()
        waitForValue(canvas, "Nothing selected")

        // Pinch zooms around the middle: the centred point stays put.
        selectGardenAndSleepLog(app, canvas)
        canvas.pinch(withScale: 2.5, velocity: 2)
        settle()
        attach(app, "after pinch in")
        centre.tap()
        waitForValue(canvas, "Selected: Garden plans")

        // Drag on the point moves it off the middle; a tap there now misses.
        selectGardenAndSleepLog(app, canvas)
        centre.press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)))
        attach(app, "after dragging the point")
        centre.tap()
        waitForValue(canvas, "Nothing selected")
        waitForLabel(requests(app), "requests: 1")
    }

    /// Search picks (and centres) Garden plans, the list adds Sleep log.
    @MainActor
    private func selectGardenAndSleepLog(_ app: XCUIApplication, _ canvas: XCUIElement) {
        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas, "Selected: Garden plans")
        settle()
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        app.buttons["brain.list.row.N3"].tap()
        closeSheet(app)
        waitForValue(canvas, "2 selected")
    }
}
