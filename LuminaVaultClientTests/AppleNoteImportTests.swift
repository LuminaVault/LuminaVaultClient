@testable import LuminaVaultClient
import XCTest

/// Apple Notes → vault: identity and dedupe. A re-run of the Shortcut must
/// update the same vault note, and skip notes that did not change.
final class AppleNoteImportTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_790_000_000)

    func testSameNoteGetsTheSameCaptureIDAfterAnEdit() {
        let before = AppleNoteImport(title: "Groceries", body: "milk", created: created, modified: nil)
        let after = AppleNoteImport(title: "Groceries", body: "milk, eggs", created: created, modified: .now)
        XCTAssertEqual(before.captureID, after.captureID)
        XCTAssertNotEqual(before.contentHash, after.contentHash)
    }

    func testDifferentNotesDoNotCollide() {
        let a = AppleNoteImport(title: "Groceries", body: "", created: created, modified: nil)
        let b = AppleNoteImport(title: "Groceries", body: "", created: created.addingTimeInterval(60), modified: nil)
        let c = AppleNoteImport(title: "Trip", body: "", created: created, modified: nil)
        XCTAssertEqual(Set([a.captureID, b.captureID, c.captureID]).count, 3)
    }

    func testCaptureIDIsAVersion5ShapedUUID() {
        let id = AppleNoteImport(title: "x", body: "", created: nil, modified: nil).captureID.uuidString
        let chars = Array(id)
        XCTAssertEqual(chars[14], "5")
        XCTAssertTrue(["8", "9", "A", "B"].contains(chars[19]))
    }

    func testMarkdownDropsARepeatedTitleAndCitesTheSource() {
        let note = AppleNoteImport(title: "Groceries", body: "Groceries\nmilk\neggs", created: created, modified: nil)
        XCTAssertTrue(note.markdown.hasPrefix("# Groceries\n\nmilk\neggs\n\n_From Apple Notes, created "))
    }

    func testEmptyAndUntitledNotes() {
        XCTAssertTrue(AppleNoteImport(title: "  ", body: "\n", created: nil, modified: nil).isEmpty)
        XCTAssertEqual(AppleNoteImport(title: " ", body: "text", created: nil, modified: nil).displayTitle, "Untitled note")
    }

    func testLedgerSkipsUnchangedNotesOnly() throws {
        let suite = "AppleNoteImportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = AppleNoteImportLedger(defaults: defaults)
        let note = AppleNoteImport(title: "Groceries", body: "milk", created: created, modified: nil)

        XCTAssertTrue(ledger.needsUpload(note))
        ledger.recordUpload(note)
        XCTAssertFalse(ledger.needsUpload(note))

        let edited = AppleNoteImport(title: "Groceries", body: "milk, eggs", created: created, modified: nil)
        XCTAssertTrue(ledger.needsUpload(edited))
    }
}
