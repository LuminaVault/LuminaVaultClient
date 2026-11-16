import Foundation
@testable import LuminaVaultClient
import XCTest

@MainActor
final class VaultImportViewModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultImportViewModelTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Second Brain", isDirectory: true)
        try write("Lore/The Last Light.md", "# The Last Light\n\n[[Ada]]")
        try write("Lore/People/Ada.markdown", "# Ada")
        try write("Welcome.md", "# Welcome")
        try write("Inbox.txt", "plain text")
        try write(".obsidian/snippets/hidden.md", "# app state")
        try write("Lore/.draft.md", "# hidden")
        try write("Attachments/map.png", "PNG")
        try write("Empty.md", "   ")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testScanKeepsNotesAndLeavesOutHiddenFilesAndAttachments() async {
        let viewModel = VaultImportViewModel(client: RecordingImportClient())
        await viewModel.scan(root)

        let byName = Dictionary(uniqueKeysWithValues: viewModel.folders.map { ($0.name, Set($0.files.map(\.relPath))) })
        XCTAssertEqual(byName["Lore"], ["The Last Light.md", "People/Ada.markdown"])
        XCTAssertEqual(byName["Second Brain"], ["Welcome.md", "Inbox.txt"], "root notes go to a Space named after the vault")
        XCTAssertNil(byName[".obsidian"])
        XCTAssertNil(byName["Attachments"])
    }

    func testImportKeepsExistingNotesByDefaultAndListsWhatNeedsALook() async {
        let client = RecordingImportClient(statusFor: { $0 == "The Last Light.md" ? "exists" : "imported" })
        let viewModel = VaultImportViewModel(client: client)
        await viewModel.scan(root)
        viewModel.selected = ["Lore"]

        await viewModel.runImport()

        let calls = await client.calls
        XCTAssertEqual(calls.map(\.space), ["Lore"])
        XCTAssertEqual(calls.map(\.onConflict), ["skip"])
        XCTAssertEqual(viewModel.phase, .done)
        XCTAssertEqual(viewModel.resultText, "Imported 1 · kept 1 existing")
        XCTAssertEqual(viewModel.needsAttention.map(\.path), ["The Last Light.md"])
    }

    func testReplaceSendsOverwrite() async {
        let client = RecordingImportClient()
        let viewModel = VaultImportViewModel(client: client)
        await viewModel.scan(root)
        viewModel.selected = ["Lore"]
        viewModel.keepExisting = false

        await viewModel.runImport()

        let onConflict = await client.calls.map(\.onConflict)
        XCTAssertEqual(onConflict, ["overwrite"])
    }
}

private actor RecordingImportClient: VaultImportClientProtocol {
    struct Call: Sendable {
        let space: String
        let paths: [String]
        let onConflict: String?
    }

    private(set) var calls: [Call] = []
    private let statusFor: @Sendable (String) -> String

    init(statusFor: @escaping @Sendable (String) -> String = { _ in "imported" }) {
        self.statusFor = statusFor
    }

    func bulk(space: String, files: [VaultBulkFile], onConflict: String?) async throws -> VaultBulkResponse {
        calls.append(Call(space: space, paths: files.map(\.path), onConflict: onConflict))
        let results = files.map { VaultBulkFileResult(path: $0.path, savedPath: "lore/\($0.path.lowercased())", status: statusFor($0.path)) }
        let imported = results.filter { $0.status == "imported" }.count
        return VaultBulkResponse(
            spaceID: UUID().uuidString, spaceSlug: "lore",
            imported: imported, skipped: results.count - imported, failed: 0, files: results
        )
    }
}
