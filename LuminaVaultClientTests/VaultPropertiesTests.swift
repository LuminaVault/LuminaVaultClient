// LuminaVaultClient/LuminaVaultClientTests/VaultPropertiesTests.swift
// Backlog E8.5 — read-only properties and saved views: decoding the Go
// shapes, stripping frontmatter, formatting values, and the table model.

import Foundation
import XCTest
@testable import LuminaVaultClient

@MainActor
final class VaultPropertiesTests: XCTestCase {
    private func decode<T: Decodable>(_: T.Type, _ json: String) throws -> T {
        try JSONDecoder.hvDefault.decode(T.self, from: Data(json.utf8))
    }

    private let fileJSON = #"{"id":"6f1f8a52-0f3a-4f39-9a52-2d1bb0a7f001","path":"projects/plan.md","contentType":"text/markdown","sizeBytes":10,"sha256":"aa"}"#

    // MARK: Decoding

    func testPropertyNamesKeepTheirCaseAndUnderscores() throws {
        let out = try decode(VaultFilePropertiesListResponse.self, #"""
        {"files":[{"path":"a.md","properties":{"date_created":"2026-11-18","Status":"Doing"},"propertiesError":null}]}
        """#)
        XCTAssertEqual(out.files[0].properties?.keys.sorted(), ["Status", "date_created"])
    }

    func testValuesDecodeByShape() throws {
        let out = try decode([String: VaultPropertyValue].self, #"""
        {"s":"x","n":4,"f":2.5,"b":true,"one":1,"l":["a",2],"z":null,"m":{"k":"v"}}
        """#)
        XCTAssertEqual(out["s"], .string("x"))
        XCTAssertEqual(out["n"], .number(4))
        XCTAssertEqual(out["f"], .number(2.5))
        XCTAssertEqual(out["b"], .bool(true))
        XCTAssertEqual(out["one"], .number(1), "1 is a number, not true")
        XCTAssertEqual(out["l"], .list([.string("a"), .number(2)]))
        XCTAssertEqual(out["z"], .null)
        XCTAssertEqual(out["m"], .map(["k": .string("v")]))
    }

    func testUnknownTypeReadsAsTextAndReservedNamesWin() throws {
        let out = try decode(VaultPropertyTypesResponse.self, #"""
        {"types":[{"name":"Rating","type":"number","options":[]},{"name":"mood","type":"emoji"},{"name":"due","type":"text"}]}
        """#)
        let types = VaultPropertyTypes(out.types)
        XCTAssertEqual(types.kind(of: "rating"), .number)
        XCTAssertEqual(types.kind(of: "mood"), .text)
        XCTAssertEqual(types.kind(of: "due"), .date)
        XCTAssertEqual(types.kind(of: "tags"), .multiselect)
        XCTAssertEqual(types.kind(of: "anything"), .text)
    }

    func testQueryResponseDecodesRowsColumnsGroupsAndCursor() throws {
        let out = try decode(VaultQueryResponse.self, """
        {"rows":[{"file":\(fileJSON),"properties":{"status":"Doing"}}],
         "columns":[{"name":"status","type":"select","options":["Doing","Done"]}],
         "groups":[{"value":"Doing","count":1},{"count":3}],"nextCursor":"o:100"}
        """)
        XCTAssertEqual(out.rows.first?.file.path, "projects/plan.md")
        XCTAssertEqual(out.rows.first?.properties["status"], .string("Doing"))
        XCTAssertEqual(out.columns, [VaultPropertyTypeDTO(name: "status", type: .select, options: ["Doing", "Done"])])
        XCTAssertEqual(
            out.groups,
            [VaultQueryGroup(value: .string("Doing"), count: 1), VaultQueryGroup(value: nil, count: 3)]
        )
        XCTAssertEqual(out.nextCursor, "o:100")
    }

    // MARK: Requests

    private func view(group: String? = nil, columns: [VaultViewColumn] = []) -> VaultSavedView {
        VaultSavedView(
            id: "v1",
            name: "Projects",
            scope: VaultQueryScope(folder: "projects"),
            columns: columns,
            filter: [VaultQueryFilter(property: "status", op: "neq", value: .string("Done"))],
            sort: [],
            group: group
        )
    }

    func testQueryRequestCarriesTheViewInCamelCaseAndOmitsEmptyParts() throws {
        let request = VaultQueryRequest(view: view(group: ""), limit: 100, cursor: "o:100")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["limit"] as? Int, 100)
        XCTAssertEqual(json?["cursor"] as? String, "o:100")
        XCTAssertEqual((json?["scope"] as? [String: Any])?["folder"] as? String, "projects")
        XCTAssertNil(json?["sort"])
        XCTAssertNil(json?["group"])
        let filter = (json?["filter"] as? [[String: Any]])?.first
        XCTAssertEqual(filter?["op"] as? String, "neq")
        XCTAssertEqual(filter?["value"] as? String, "Done")
    }

    func testEndpoints() {
        XCTAssertEqual(
            VaultEndpoints.FileProperties(filePath: "a b+c.md").path,
            "/v1/vault/files?q=a%20b%2Bc.md&limit=50"
        )
        XCTAssertEqual(VaultEndpoints.PropertyTypes().path, "/v1/vault/property-types")
        XCTAssertEqual(VaultEndpoints.Views().path, "/v1/vault/views")
        XCTAssertEqual(VaultEndpoints.Query(request: VaultQueryRequest(view: view())).method, .post)
    }

    // MARK: Display

    func testStripFrontmatter() {
        XCTAssertEqual(NoteFrontmatter.strip("---\nstatus: Doing\n---\n\n# Plan\n"), "# Plan\n")
        XCTAssertEqual(NoteFrontmatter.strip("\u{FEFF}---\r\na: 1\r\n...\r\nBody"), "Body")
        XCTAssertEqual(NoteFrontmatter.strip("---\nnever closed\n"), "---\nnever closed\n")
        XCTAssertEqual(NoteFrontmatter.strip("# No block\n---\n"), "# No block\n---\n")
    }

    func testValueText() {
        XCTAssertEqual(VaultPropertyDisplay.text(.number(4), kind: .number), "4")
        XCTAssertEqual(VaultPropertyDisplay.text(.number(2.5), kind: .number), "2.5")
        XCTAssertEqual(VaultPropertyDisplay.text(.bool(true), kind: .checkbox), "Yes")
        XCTAssertEqual(VaultPropertyDisplay.text(.list([.string("a"), .string("b")]), kind: .multiselect), "a, b")
        XCTAssertEqual(VaultPropertyDisplay.text(.string("not a date"), kind: .date), "not a date")
        XCTAssertNotEqual(VaultPropertyDisplay.text(.string("2026-11-18"), kind: .date), "2026-11-18")
    }

    func testLinksAreHTTPOnly() {
        XCTAssertNotNil(VaultPropertyDisplay.link(.string("https://example.com")))
        XCTAssertNil(VaultPropertyDisplay.link(.string("javascript:alert(1)")))
        XCTAssertNil(VaultPropertyDisplay.link(.number(1)))
    }

    func testReaderRowsSortByNameAndLeaveOutTheTitle() {
        let rows = NotePropertyRow.rows(
            ["title": .string("Plan"), "status": .string("Doing"), "due": .string("2026-12-01")],
            types: VaultPropertyTypes([VaultPropertyTypeDTO(name: "status", type: .select)])
        )
        XCTAssertEqual(rows.map(\.name), ["due", "status"])
        XCTAssertEqual(rows.map(\.kind), [.date, .select])
    }

    // MARK: Table model

    private func row(_ name: String, _ properties: [String: VaultPropertyValue]) throws -> VaultQueryRow {
        let id = UUID().uuidString
        return try decode(
            VaultQueryRow.self,
            #"{"file":{"id":"\#(id)","path":"projects/\#(name).md","contentType":"text/markdown","sizeBytes":1,"sha256":"x"},"properties":{}}"#
        )
        .with(properties)
    }

    func testColumnsFollowTheViewOrderElseWhatIsPresent() {
        let present = [
            VaultPropertyTypeDTO(name: "rating", type: .number),
            VaultPropertyTypeDTO(name: "status", type: .select),
        ]
        XCTAssertEqual(VaultViewTableModel.columns(present: present, order: []).map(\.name), ["rating", "status"])
        let ordered = VaultViewTableModel.columns(present: present, order: [
            VaultViewColumn(property: "status", width: nil), VaultViewColumn(property: "due", width: nil),
        ])
        XCTAssertEqual(ordered, [.init(name: "status", kind: .select), .init(name: "due", kind: .date)])
    }

    func testSectionsSplitWhereTheGroupChanges() throws {
        let rows = try [
            row("a", ["status": .string("Doing")]),
            row("b", ["status": .string("Doing")]),
            row("c", ["status": .string("Done")]),
            row("d", [:]),
        ]
        let sections = VaultViewTableModel.sections(
            rows: rows,
            group: "status",
            kind: .select,
            groups: [VaultQueryGroup(value: .string("Doing"), count: 2), VaultQueryGroup(value: nil, count: 1)]
        )
        XCTAssertEqual(sections.map(\.title), ["Doing", "Done", "No value"])
        XCTAssertEqual(sections.map(\.rows.count), [2, 1, 1])
        XCTAssertEqual(sections.map(\.count), [2, nil, 1])
        XCTAssertEqual(VaultViewTableModel.sections(rows: rows, group: nil, kind: .text, groups: []).count, 1)
    }

    func testLoadThenLoadMoreFollowsTheCursor() async throws {
        let client = MockVaultClient()
        let first = try row("a", ["status": .string("Doing")])
        let second = try row("b", ["status": .string("Done")])
        client.queryResults = [
            .success(VaultQueryResponse(
                rows: [first],
                columns: [VaultPropertyTypeDTO(name: "status", type: .select)],
                groups: nil,
                nextCursor: "o:1"
            )),
            .success(VaultQueryResponse(rows: [first, second], columns: [], groups: nil, nextCursor: nil)),
        ]
        let model = VaultViewTableModel(view: view(), vaultClient: client)
        await model.load()
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.columns.map(\.name), ["status"])
        XCTAssertEqual(model.nextCursor, "o:1")
        await model.loadMore()
        XCTAssertEqual(
            model.rows.map(\.file.path),
            ["projects/a.md", "projects/b.md"],
            "the repeated row is not added twice"
        )
        XCTAssertNil(model.nextCursor)
        XCTAssertEqual(client.queryRequests.map(\.cursor), [nil, "o:1"])
        XCTAssertEqual(client.queryRequests.first?.scope, VaultQueryScope(folder: "projects"))
    }

    func testLoadFailureShowsAnError() async {
        let client = MockVaultClient()
        client.queryResults = [.failure(URLError(.notConnectedToInternet))]
        let model = VaultViewTableModel(view: view(), vaultClient: client)
        await model.load()
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.hasLoaded)
    }

    func testFakesSeePropertiesAsOff() async throws {
        let client = MockVaultClient()
        let types = try await client.propertyTypes()
        XCTAssertNil(types)
    }
}

private extension VaultQueryRow {
    func with(_ properties: [String: VaultPropertyValue]) -> VaultQueryRow {
        VaultQueryRow(file: file, properties: properties)
    }
}
