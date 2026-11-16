// LuminaVaultClient/LuminaVaultClientTests/NoteShortcutsViewModelTests.swift
// Backlog E6.4 — Today's note and New from template.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class NoteShortcutsViewModelTests: XCTestCase {
    private func file(_ path: String) -> VaultFileDTO {
        VaultFileDTO(id: UUID(), path: path, contentType: "text/markdown", sizeBytes: 1, sha256: "")
    }

    private func list(_ paths: [String]) -> VaultFileListResponse {
        VaultFileListResponse(files: paths.map(file), limit: 100, nextBefore: nil)
    }

    private func makeVM(_ client: MockVaultClient) -> NoteShortcutsViewModel {
        NoteShortcutsViewModel(client: client, timeZone: { "Europe/Lisbon" })
    }

    func testTodayOpensTheDailyNoteInTheUsersZone() async {
        let client = MockVaultClient()
        let vm = makeVM(client)
        await vm.openToday()
        XCTAssertEqual(vm.openedNote?.path, "daily/2026-11-16.md")
        XCTAssertEqual(client.dailyNoteZones, ["Europe/Lisbon"])
        XCTAssertNil(vm.error)
    }

    func testTodayFailureShowsAnError() async {
        let client = MockVaultClient()
        client.dailyNoteResult = .failure(URLError(.notConnectedToInternet))
        let vm = makeVM(client)
        await vm.openToday()
        XCTAssertNil(vm.openedNote)
        XCTAssertEqual(vm.error, "Could not open today's note.")
    }

    func testSeedsStarterTemplatesOnlyWhenNoneExist() async {
        let client = MockVaultClient()
        client.listFilesQueue = [list([]), list(["templates/project.md", "templates/daily.md", "templates/cover.png"])]
        let vm = makeVM(client)
        await vm.loadTemplates()
        XCTAssertEqual(client.seedTemplatesCalls, 1)
        XCTAssertEqual(vm.templates.map(\.path), ["templates/daily.md", "templates/project.md"])
        XCTAssertEqual(vm.selectedTemplate, "templates/daily.md")
        XCTAssertEqual(client.listFilesCalls.first?.spaceSlug, "templates")

        client.listFilesQueue = [list(["templates/meeting.md"])]
        await vm.loadTemplates()
        XCTAssertEqual(client.seedTemplatesCalls, 1)
    }

    func testCreateSendsTheFileNameTitleAndZone() async {
        let client = MockVaultClient()
        client.listFilesQueue = [list(["templates/meeting.md"])]
        let vm = makeVM(client)
        await vm.loadTemplates()
        XCTAssertFalse(vm.canCreate)
        vm.title = "  Weekly sync "
        XCTAssertTrue(vm.canCreate)

        let created = await vm.create()
        XCTAssertTrue(created)
        XCTAssertEqual(
            client.noteFromTemplateRequests,
            [VaultFromTemplateRequest(template: "meeting.md", title: "Weekly sync", tz: "Europe/Lisbon")]
        )
        XCTAssertEqual(vm.openedNote?.path, "inbox/note.md")
        XCTAssertEqual(vm.title, "")
    }

    func testTakenNameExplainsItself() async {
        let client = MockVaultClient()
        client.listFilesQueue = [list(["templates/meeting.md"])]
        client.noteFromTemplateResult = .failure(APIError.httpError(statusCode: 409, data: Data()))
        let vm = makeVM(client)
        await vm.loadTemplates()
        vm.title = "Garden"
        let created = await vm.create()
        XCTAssertFalse(created)
        XCTAssertNil(vm.openedNote)
        XCTAssertEqual(vm.error, "A note with that name already exists. Pick another title.")
    }

    func testLabels() {
        XCTAssertEqual(NoteShortcutsViewModel.label("templates/weekly-review.md"), "Weekly review")
        XCTAssertEqual(NoteShortcutsViewModel.label("templates/daily.md"), "Daily")
        XCTAssertEqual(NoteShortcutsViewModel.fileName("templates/meeting.md"), "meeting.md")
    }

    func testFromTemplateRequestEncodesCamelCase() throws {
        let space = UUID()
        let data = try JSONEncoder().encode(
            VaultFromTemplateRequest(template: "a.md", title: "T", spaceId: space, tz: "UTC")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["spaceId"] as? String, space.uuidString)
        XCTAssertNil(json["space_id"])
    }
}
