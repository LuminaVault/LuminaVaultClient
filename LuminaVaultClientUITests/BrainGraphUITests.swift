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
        // A test stopped by a failure skips its own cleanup: every launch
        // starts upright.
        XCUIDevice.shared.orientation = .portrait
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

    /// A response with the same counts and `generatedAt` as the one before
    /// is still a new response: the screen must show it.
    @MainActor
    func testEveryLandedResponseIsShown() {
        let app = launch("sameStamp")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        app.buttons["brain.filter.vault.Work"].tap()
        closeSheet(app)
        waitForLabel(requests(app), "requests: 2")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "moved gar", pick: "Moved garden plans")
        waitForValue(canvas(app), "Selected: Moved garden plans")
    }

    /// A selected point that a filter hides leaves the selection.
    @MainActor
    func testAFilterThatHidesTheSelectionClearsIt() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas(app), "Selected: Garden plans")
        openFilters(app)
        app.buttons["brain.filter.vault.Personal"].tap()
        closeSheet(app)
        waitForValue(canvas(app), "Nothing selected")
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        let row = app.buttons["brain.list.row.N6"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["brain.list.row.N1"].exists)
        XCTAssertFalse(row.isSelected)
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
        let retry = app.buttons["brain.status.retry"].frame
        XCTAssertGreaterThanOrEqual(retry.height, 44, "Retry is a full tap target")
        XCTAssertGreaterThanOrEqual(retry.width, 44, "Retry is a full tap target")
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

    /// The element the harness puts on the probed point (`-BrainUITestProbe`).
    @MainActor
    private func probe(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["brain.uitest.probe"]
    }

    /// Where the probed point is on screen now.
    @MainActor
    private func probed(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGPoint {
        let mark = probe(app)
        XCTAssertTrue(mark.waitForExistence(timeout: 8), "no probe", file: file, line: line)
        return CGPoint(x: mark.frame.midX, y: mark.frame.midY)
    }

    @MainActor
    private func at(_ app: XCUIApplication, _ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    /// Search puts a point in the middle of the part of the canvas above the
    /// tray; everything else is driven from where the probe says it is.
    /// Selection shows in the canvas's accessibility value.
    @MainActor
    func testCanvasGestures() {
        let app = launch("graph", ["-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        let canvas = canvas(app)
        let corner = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04))

        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas, "Selected: Garden plans")
        settle()
        attach(app, "centred on Garden plans")
        let here = probed(app)
        // Centred across, and above the middle by half the tray.
        XCTAssertEqual(here.x, canvas.frame.midX, accuracy: 2)
        XCTAssertLessThan(here.y, canvas.frame.midY - 20)
        let point = at(app, here)

        // Tap the only selected point: it toggles off. Tap again: back on.
        point.tap()
        waitForValue(canvas, "Nothing selected")
        point.tap()
        waitForValue(canvas, "Selected: Garden plans")

        // Tap the background: clears.
        corner.tap()
        waitForValue(canvas, "Nothing selected")

        // Long press adds to the selection without replacing it.
        point.tap()
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        app.buttons["brain.list.row.N3"].tap()
        closeSheet(app)
        waitForValue(canvas, "2 selected")
        point.press(forDuration: 0.9)
        waitForValue(canvas, "Selected: Sleep log")
        point.press(forDuration: 0.9)
        waitForValue(canvas, "2 selected")

        // Two selected from here on, so a tap that hits Garden plans reads
        // "Selected: Garden plans" and one that misses reads "Nothing selected".

        // Drag on the background pans the view: the point is not there now.
        corner.press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
        settle()
        attach(app, "after panning")
        point.tap()
        waitForValue(canvas, "Nothing selected")

        // Pinch zooms; the point is still where the probe says.
        selectGardenAndSleepLog(app, canvas)
        canvas.pinch(withScale: 2.5, velocity: 2)
        settle()
        attach(app, "after pinch in")
        at(app, probed(app)).tap()
        waitForValue(canvas, "Selected: Garden plans")

        // Drag on the point moves it; a tap where it was now misses.
        selectGardenAndSleepLog(app, canvas)
        let before = probed(app)
        at(app, before).press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)))
        attach(app, "after dragging the point")
        at(app, before).tap()
        waitForValue(canvas, "Nothing selected")
        waitForLabel(requests(app), "requests: 1")
    }

    /// A double tap on a point nobody selected opens it: the first tap
    /// selects it and brings the tray, which must not move the point out from
    /// under the second.
    @MainActor
    func testDoubleTapOpensAnUnselectedPoint() {
        let app = launch("graph", ["-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        settle()
        waitForValue(canvas(app), "Nothing selected")
        at(app, probed(app)).doubleTap()
        XCTAssertTrue(app.staticTexts["brain.detail.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["brain.detail.title"].label, "Garden plans")
        attach(app, "double tap opened Garden plans")
        waitForLabel(requests(app), "requests: 1")
    }

    /// Selecting never moves the camera: the tray comes up over the graph and
    /// the point stays exactly where it was.
    @MainActor
    func testSelectingDoesNotMoveThePoint() {
        let app = launch("graph", ["-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        settle()
        let canvas = canvas(app)
        let frame = canvas.frame
        let before = probed(app)
        attach(app, "before selecting")
        at(app, before).tap()
        waitForValue(canvas, "Selected: Garden plans")
        XCTAssertTrue(app.staticTexts["brain.tray.count"].waitForExistence(timeout: 5))
        settle()
        attach(app, "after selecting")
        let after = probed(app)
        XCTAssertEqual(after.x, before.x, accuracy: 1)
        XCTAssertEqual(after.y, before.y, accuracy: 1)
        XCTAssertEqual(canvas.frame, frame)
        // And back: clearing takes the tray away without a move either.
        app.buttons["brain.tray.clear"].tap()
        waitForValue(canvas, "Nothing selected")
        settle()
        let cleared = probed(app)
        XCTAssertEqual(cleared.x, before.x, accuracy: 1)
        XCTAssertEqual(cleared.y, before.y, accuracy: 1)
    }

    /// Back on the tab after the graph has aged: one new request, and the
    /// same data keeps the selection and the point where it was.
    @MainActor
    func testAnOldGraphIsFetchedAgainOnReturnKeepingSelectionAndPlace() {
        let app = launch("graph", ["-BrainUITestControls", "YES", "-BrainUITestRefreshAge", "1", "-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        settle()
        let canvas = canvas(app)
        at(app, probed(app)).tap()
        waitForValue(canvas, "Selected: Garden plans")
        settle()
        let before = probed(app)
        control(app, "leave").tap()
        control(app, "return").tap()
        waitForLabel(requests(app), "requests: 2")
        settle()
        waitForValue(canvas, "Selected: Garden plans")
        let after = probed(app)
        XCTAssertEqual(after.x, before.x, accuracy: 1)
        XCTAssertEqual(after.y, before.y, accuracy: 1)
        // (A graph younger than the age asks nothing: the store's unit tests
        // hold that; a one-second age cannot be beaten by UI taps.)
    }

    // MARK: tray

    @MainActor
    private func trayCount(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["brain.tray.count"]
    }

    @MainActor
    private func trayAction(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["brain.tray.action.\(id)"]
    }

    @MainActor
    private func lastQuery(_ app: XCUIApplication) -> String {
        requests(app).value as? String ?? ""
    }

    @MainActor
    func testTwoSelectedEnableExplain() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        XCTAssertTrue(trayCount(app).waitForExistence(timeout: 5))
        waitForLabel(trayCount(app), "1 selected")
        XCTAssertFalse(trayAction(app, "explain").isEnabled)
        XCTAssertTrue(trayAction(app, "open").isEnabled)
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        app.buttons["brain.list.row.N3"].tap()
        closeSheet(app)
        waitForLabel(trayCount(app), "2 selected")
        XCTAssertTrue(trayAction(app, "explain").isEnabled)
        XCTAssertFalse(trayAction(app, "open").isEnabled)
        XCTAssertFalse(trayAction(app, "focus").isEnabled)
        attach(app, "tray with two selected")
        waitForLabel(requests(app), "requests: 1")
    }

    /// Picks rows in the List (taps add to the selection). Works on iPhone
    /// and iPad alike, where search suggestions present differently.
    @MainActor
    private func selectFromTheList(_ app: XCUIApplication, _ ids: [String]) {
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        for id in ids {
            let row = app.buttons["brain.list.row.\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        closeSheet(app)
    }

    /// Every tray control is at least 44 × 44 pt.
    @MainActor
    private func assertFullTargets(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var controls = ["open", "focus", "group", "explain", "ask"].map { ("action \($0)", trayAction(app, $0)) }
        controls.append(("Clear", app.buttons["brain.tray.clear"]))
        controls.append(("remove Garden plans", app.buttons["Remove Garden plans (Note)"]))
        controls.append(("remove Sleep log", app.buttons["Remove Sleep log (Memory)"]))
        for (name, control) in controls {
            XCTAssertTrue(control.exists, "\(name) exists", file: file, line: line)
            // Rounded: a frame inside a scroll view can read 43.99999999999994.
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.height.rounded(), 44, "\(name) height \(frame.height)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.width.rounded(), 44, "\(name) width \(frame.width)", file: file, line: line)
        }
    }

    @MainActor
    func testTrayTargetsAreFullSize() {
        let app = launch("graph", ["-BrainUITestHideRequests", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectFromTheList(app, ["N1", "N3"])
        waitForLabel(trayCount(app), "2 selected")
        assertFullTargets(app)
        attach(app, "tray light")
    }

    @MainActor
    func testTrayAtAccessibilitySize() {
        let app = launch("graph", ["-BrainUITestHideRequests", "YES", "-BrainUITestTypeSize", "accessibility3"])
        XCTAssertTrue(counts(app).waitForExistence(timeout: 8))
        selectFromTheList(app, ["N1", "N3"])
        waitForLabel(trayCount(app), "2 selected")
        assertFullTargets(app)
        attach(app, "tray accessibility3")
    }

    /// Large type in landscape: the tray stops at half the canvas and
    /// scrolls, leaving the search bar and the graph above it uncovered.
    @MainActor
    func testTrayAtAccessibilitySizeInLandscapeLeavesTheSearchBar() {
        let app = launch("graph", ["-BrainUITestHideRequests", "YES", "-BrainUITestTypeSize", "accessibility3"])
        XCTAssertTrue(counts(app).waitForExistence(timeout: 8))
        selectFromTheList(app, ["N1", "N3"])
        waitForLabel(trayCount(app), "2 selected")
        XCUIDevice.shared.orientation = .landscapeLeft
        settle()
        let tray = app.descendants(matching: .any)["brain.tray"].frame
        let graph = canvas(app).frame
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.exists)
        // The tray's bar material runs on into the bottom safe area under the
        // search field, as in portrait; its top edge is what the cap holds.
        XCTAssertGreaterThanOrEqual(
            tray.minY.rounded(), (graph.maxY - graph.height / 2).rounded() - 1, "tray \(tray), canvas \(graph)"
        )
        XCTAssertTrue(field.isHittable, "search \(field.frame)")
        attach(app, "tray accessibility3 landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTrayInDark() {
        let app = launch("graph", ["-BrainUITestHideRequests", "YES", "-BrainUITestScheme", "dark"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectFromTheList(app, ["N1", "N3"])
        waitForLabel(trayCount(app), "2 selected")
        attach(app, "tray dark")
    }

    @MainActor
    func testRemovingAChipDeselectsIt() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectGardenAndSleepLog(app, canvas(app))
        waitForLabel(trayCount(app), "2 selected")
        app.buttons["Remove Garden plans (Note)"].tap()
        waitForLabel(trayCount(app), "1 selected")
        waitForValue(canvas(app), "Selected: Sleep log")
        XCTAssertFalse(app.buttons["Remove Garden plans (Note)"].exists)
        XCTAssertTrue(app.buttons["Remove Sleep log (Memory)"].exists)
    }

    @MainActor
    func testClearEmptiesTheTray() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectGardenAndSleepLog(app, canvas(app))
        app.buttons["brain.tray.clear"].tap()
        waitForValue(canvas(app), "Nothing selected")
        XCTAssertFalse(trayCount(app).exists)
    }

    @MainActor
    func testFocusMakesOneRequestWithoutAuthorLinks() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        XCTAssertTrue(lastQuery(app).contains("author"), "the full graph asks for author links")
        search(app, "gard", pick: "Garden plans")
        trayAction(app, "focus").tap()
        waitForLabel(requests(app), "requests: 2")
        settle()
        waitForLabel(requests(app), "requests: 2")
        let query = lastQuery(app)
        XCTAssertTrue(query.contains("focus=N1"), query)
        XCTAssertFalse(query.contains("author"), query)
        XCTAssertTrue(app.buttons["Full graph"].exists)
    }

    @MainActor
    func testAHiddenSelectedPointLeavesTheTray() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        app.buttons["brain.more"].tap()
        app.buttons["List"].tap()
        app.buttons["brain.list.row.N6"].tap()
        closeSheet(app)
        waitForLabel(trayCount(app), "2 selected")
        openFilters(app)
        app.buttons["brain.filter.vault.Personal"].tap()
        closeSheet(app)
        waitForLabel(trayCount(app), "1 selected")
        // The selection itself drops the hidden point, not only the tray.
        waitForValue(canvas(app), "Selected: Meeting notes")
        XCTAssertFalse(app.buttons["Remove Garden plans (Note)"].exists)
        XCTAssertTrue(app.buttons["Remove Meeting notes (Note)"].exists)
    }

    @MainActor
    func testAskPrefillsWithoutSending() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectGardenAndSleepLog(app, canvas(app))
        trayAction(app, "ask").tap()
        let question = app.textViews["brain.reasoning.question"].exists
            ? app.textViews["brain.reasoning.question"] : app.textFields["brain.reasoning.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertEqual(question.value as? String, "What connects Garden plans, Sleep log?")
        XCTAssertFalse(app.staticTexts["Answer"].exists)
        XCTAssertTrue(app.staticTexts["Ask how your notes and memories connect."].exists)
        attach(app, "ask prefilled")
    }

    /// The reasoning sheet leaves the graph usable; opening Filters from
    /// behind it closes it first, so the filter sheet does present.
    @MainActor
    func testFiltersOpenOverTheReasoningSheet() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        trayAction(app, "ask").tap()
        XCTAssertTrue(app.navigationBars["Ask your graph"].waitForExistence(timeout: 5))
        app.buttons["brain.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Ask your graph"].exists)
    }

    @MainActor
    func testExplainSendsTheQuestion() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectGardenAndSleepLog(app, canvas(app))
        trayAction(app, "explain").tap()
        XCTAssertTrue(app.staticTexts["Answer"].waitForExistence(timeout: 5))
        attach(app, "explain answered")
    }

    @MainActor
    func testOpenShowsANote() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        trayAction(app, "open").tap()
        XCTAssertTrue(app.staticTexts["brain.detail.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["brain.detail.title"].label, "Garden plans")
        XCTAssertTrue(app.staticTexts["Personal"].exists)
        attach(app, "note detail")
        waitForLabel(requests(app), "requests: 1")
    }

    // MARK: Constellation

    @MainActor
    private func constellation(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["brain.constellation"]
    }

    @MainActor
    private func pickView(_ app: XCUIApplication, _ title: String) {
        app.buttons["brain.more"].tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// The switch lives outside the renderer: no request, same selection.
    @MainActor
    func testSwitchingToTheConstellationAndBackKeepsTheSelection() {
        let app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        search(app, "gard", pick: "Garden plans")
        waitForValue(canvas(app), "Selected: Garden plans")
        pickView(app, "Constellation")
        XCTAssertTrue(constellation(app).waitForExistence(timeout: 8))
        waitForValue(constellation(app), "Selected: Garden plans")
        XCTAssertFalse(canvas(app).exists)
        settle()
        attach(app, "constellation with Garden plans selected")
        pickView(app, "2D")
        XCTAssertTrue(canvas(app).waitForExistence(timeout: 5))
        waitForValue(canvas(app), "Selected: Garden plans")
        settle()
        waitForLabel(requests(app), "requests: 1")
    }

    @MainActor
    func testTheViewChoiceSurvivesARelaunch() {
        var app = launch("graph")
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        pickView(app, "Constellation")
        XCTAssertTrue(constellation(app).waitForExistence(timeout: 8))
        app.terminate()
        app = launch("graph", ["-BrainUITestKeepPrefs", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        XCTAssertTrue(constellation(app).waitForExistence(timeout: 8))
        XCTAssertFalse(canvas(app).exists)
        // Back to 2D, so the stored choice is the default again.
        pickView(app, "2D")
        XCTAssertTrue(canvas(app).waitForExistence(timeout: 5))
    }

    /// Search centres the star; taps on it toggle, a tap on empty sky clears,
    /// a drag orbits (the middle is then empty) and a pinch zooms.
    @MainActor
    func testConstellationTapsSelect() {
        let app = launch("graph", ["-BrainUITestView", "3d", "-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        let sky = constellation(app)
        XCTAssertTrue(sky.waitForExistence(timeout: 8))
        let corner = sky.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04))
        search(app, "gard", pick: "Garden plans")
        waitForValue(sky, "Selected: Garden plans")
        settle()
        attach(app, "constellation centred on Garden plans")
        // Centred across, and above the middle by half the tray.
        let here = probed(app)
        XCTAssertEqual(here.x, sky.frame.midX, accuracy: 2)
        XCTAssertLessThan(here.y, sky.frame.midY - 20)
        let centre = at(app, here)

        centre.tap()
        waitForValue(sky, "Nothing selected")
        centre.tap()
        waitForValue(sky, "Selected: Garden plans")
        corner.tap()
        waitForValue(sky, "Nothing selected")

        centre.tap()
        waitForValue(sky, "Selected: Garden plans")
        corner.press(forDuration: 0.05, thenDragTo: sky.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.2)))
        settle()
        attach(app, "constellation after an orbit")
        waitForValue(sky, "Selected: Garden plans")
        sky.pinch(withScale: 0.5, velocity: -1)
        settle()
        attach(app, "constellation after a pinch")
        waitForValue(sky, "Selected: Garden plans")
        waitForLabel(requests(app), "requests: 1")
    }

    /// Selecting a star never moves the camera either.
    @MainActor
    func testConstellationSelectingDoesNotMoveTheStar() {
        let app = launch("graph", ["-BrainUITestView", "3d", "-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        let sky = constellation(app)
        XCTAssertTrue(sky.waitForExistence(timeout: 8))
        settle()
        // A touch holds the idle turn off for the next 5 s.
        sky.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()
        settle()
        let before = probed(app)
        at(app, before).tap()
        waitForValue(sky, "Selected: Garden plans")
        XCTAssertTrue(app.staticTexts["brain.tray.count"].waitForExistence(timeout: 5))
        settle()
        let after = probed(app)
        XCTAssertEqual(after.x, before.x, accuracy: 1)
        XCTAssertEqual(after.y, before.y, accuracy: 1)
    }

    /// A double tap on an unselected star opens it.
    @MainActor
    func testConstellationDoubleTapOpensAnUnselectedStar() {
        let app = launch("graph", ["-BrainUITestView", "3d", "-BrainUITestProbe", "N1"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        XCTAssertTrue(constellation(app).waitForExistence(timeout: 8))
        settle()
        // A touch holds the idle turn off for the next 5 s.
        constellation(app).coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()
        settle()
        at(app, probed(app)).doubleTap()
        XCTAssertTrue(app.staticTexts["brain.detail.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["brain.detail.title"].label, "Garden plans")
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

    // MARK: entry points and the active vault

    @MainActor
    private func control(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["brain.uitest.\(id)"]
    }

    @MainActor
    func testAnEntryRequestFocusesWithOneRequestAndIsAppliedOnce() {
        let app = launch("graph", ["-BrainUITestControls", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        control(app, "focusN3").tap()
        waitForLabel(requests(app), "requests: 2")
        settle()
        waitForLabel(requests(app), "requests: 2")
        XCTAssertTrue(lastQuery(app).contains("focus=N3"), lastQuery(app))
        XCTAssertTrue(app.buttons["Full graph"].exists)
        // Leaving and returning applies nothing again.
        control(app, "leave").tap()
        control(app, "return").tap()
        settle()
        waitForLabel(requests(app), "requests: 2")
        XCTAssertTrue(lastQuery(app).contains("focus=N3"), lastQuery(app))
        // A new request replaces the focus.
        control(app, "focusN6").tap()
        waitForLabel(requests(app), "requests: 3")
        XCTAssertTrue(lastQuery(app).contains("focus=N6"), lastQuery(app))
        // The full graph.
        control(app, "fullGraph").tap()
        waitForLabel(requests(app), "requests: 4")
        XCTAssertFalse(app.buttons["Full graph"].exists)
        attach(app, "entry request")
    }

    @MainActor
    func testAnEntryForAMissingNodeShowsTheMissingFocusState() {
        let app = launch("missingFocus", ["-BrainUITestControls", "YES"])
        XCTAssertTrue(
            app.staticTexts["That is no longer in your graph. It may have been deleted."].waitForExistence(timeout: 8)
        )
        app.buttons["Show full graph"].tap()
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        waitForLabel(requests(app), "requests: 2")
        control(app, "focusMissing").tap()
        XCTAssertTrue(
            app.staticTexts["That is no longer in your graph. It may have been deleted."].waitForExistence(timeout: 8)
        )
        waitForLabel(requests(app), "requests: 3")
        XCTAssertTrue(app.buttons["Show full graph"].exists, "a way back to the full graph")
        attach(app, "entry for a missing node")
    }

    @MainActor
    func testAnActiveVaultChangeElsewhereMakesNoRequestAndResetsTheAnswer() {
        let app = launch("graph", ["-BrainUITestControls", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        selectGardenAndSleepLog(app, canvas(app))
        trayAction(app, "explain").tap()
        XCTAssertTrue(app.staticTexts["Answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app, app.staticTexts["Answers draw on the knowledge in Personal."]).exists)
        app.buttons["Done"].tap()
        control(app, "leave").tap()
        control(app, "switchVault").tap()
        control(app, "return").tap()
        // The selection stays; ask the same question again.
        trayAction(app, "ask").tap()
        XCTAssertTrue(app.navigationBars["Ask your graph"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app, app.staticTexts["Answers draw on the knowledge in Work."]).exists)
        XCTAssertFalse(app.staticTexts["Answer"].exists, "an answer about the old vault is gone")
        settle()
        waitForLabel(requests(app), "requests: 1")
        attach(app, "new vault")
    }

    @MainActor
    func testTheMemoryScreenOffersShowInGraph() {
        let app = launch("memoryDetail")
        let button = app.buttons["memory.showInGraph"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        attach(app, "memory detail")
    }

    /// A memory reached through a sheet that is not the memory sheet (what
    /// Home shows after a save): the sheet goes, the Brain is focused, and one
    /// request is made.
    @MainActor
    func testShowInGraphFromARelatedSheetClosesItAndFocuses() {
        let app = launch("graph", ["-BrainUITestControls", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        control(app, "related").tap()
        XCTAssertTrue(app.navigationBars["Connects to"].waitForExistence(timeout: 5))
        app.staticTexts["Slept 7 hours."].tap()
        let show = app.buttons["memory.showInGraph"]
        XCTAssertTrue(show.waitForExistence(timeout: 8))
        show.tap()
        waitForLabel(requests(app), "requests: 2")
        XCTAssertFalse(app.navigationBars["Connects to"].waitForExistence(timeout: 2), "the sheet is gone")
        XCTAssertTrue(lastQuery(app).contains("focus=00000000-0000-0000-0000-0000000000B1"), lastQuery(app))
        XCTAssertTrue(app.buttons["Full graph"].exists)
        settle()
        waitForLabel(requests(app), "requests: 2")
        attach(app, "after show in graph")
    }

    /// A focus in a vault the filter excluded still finds it: one request,
    /// for all vaults.
    @MainActor
    func testAnEntryWithAFocusClearsTheVaultFilterInOneRequest() {
        let app = launch("graph", ["-BrainUITestControls", "YES"])
        waitForLabel(counts(app), "8 notes and memories · 10 connections")
        openFilters(app)
        app.buttons["brain.filter.vault.Work"].tap()
        closeSheet(app)
        waitForLabel(requests(app), "requests: 2")
        XCTAssertTrue(lastQuery(app).contains("vaults="), lastQuery(app))
        control(app, "focusN6").tap()
        waitForLabel(requests(app), "requests: 3")
        settle()
        waitForLabel(requests(app), "requests: 3")
        XCTAssertTrue(lastQuery(app).contains("focus=N6"), lastQuery(app))
        XCTAssertFalse(lastQuery(app).contains("vaults="), lastQuery(app))
    }
}
