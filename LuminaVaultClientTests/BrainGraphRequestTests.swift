// Port of the web app's brain-api.test.ts: same cases, same expected strings.

import Foundation
@testable import LuminaVaultClient
import Testing

struct BrainGraphRequestTests {
    private static let all = "link%2Csource%2Ctag%2Cauthor%2Centity%2Cspace"
    private let a = UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))
    private let b = UUID(uuid: (0xBB, 0xBB, 0xBB, 0xBB, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2))

    private func params(_ query: String) -> [String: String] {
        let items = URLComponents(string: query)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
    }

    @Test func buildsTheUnfocusedDefaultRequest() {
        #expect(BrainGraphRequest().query == "/v1/brain/graph?links=\(Self.all)&limit=800")
    }

    @Test func appendsSimilarLastWhenAsked() {
        #expect(BrainGraphRequest(similar: true).query
            == "/v1/brain/graph?links=\(Self.all)%2Csimilar&limit=800")
    }

    @Test func focusAddsFocusAndDepthAndDropsLimitAndAuthor() {
        let p = params(BrainGraphRequest(focus: "ABC").query)
        #expect(p["focus"] == "ABC")
        #expect(p["depth"] == "1")
        #expect(p["limit"] == nil)
        #expect(p["links"] == "link,source,tag,entity,space")
    }

    @Test func authorFocusKeepsAuthorLink() {
        let p = params(BrainGraphRequest(focus: "author:user:ABC").query)
        #expect(p["focus"] == "author:user:ABC")
        #expect(p["links"] == "link,source,tag,author,entity,space")
        for focus in ["tag:author", "entity:hermes", "AAAAAAAA-0000-4000-8000-000000000001"] {
            let links = params(BrainGraphRequest(focus: focus).query)["links"]?.split(separator: ",") ?? []
            #expect(!links.contains("author"))
        }
    }

    @Test func authorFocusIsCappedByLimitAndDepthOne() {
        let p = params(BrainGraphRequest(focus: "author:user:ABC", depth: 3).query)
        #expect(p["limit"] == "800")
        #expect(p["depth"] == "1")
        #expect(params(BrainGraphRequest(focus: "tag:author", depth: 3).query)["limit"] == nil)
    }

    @Test func similarStaysLastOnAFocusedRequest() {
        let p = params(BrainGraphRequest(focus: "ABC", similar: true).query)
        #expect(p["links"] == "link,source,tag,entity,space,similar")
    }

    @Test func joinsVaultIdsUppercased() {
        let request = BrainGraphRequest(vaults: [a, b])
        #expect(params(request.query)["vaults"]
            == "AAAAAAAA-0000-4000-8000-000000000001,BBBBBBBB-0000-4000-8000-000000000002")
        #expect(request.query.contains("vaults=AAAAAAAA-0000-4000-8000-000000000001%2CBBBBBBBB-"))
    }

    @Test func nilAndEmptyVaultsMeanAllVaults() {
        #expect(BrainGraphRequest(vaults: []).query == BrainGraphRequest().query)
        #expect(params(BrainGraphRequest().query)["vaults"] == nil)
    }

    @Test func clampsDepthToOneThroughThree() {
        func depth(_ d: Int) -> String? { params(BrainGraphRequest(focus: "ABC", depth: d).query)["depth"] }
        #expect(depth(0) == "1")
        #expect(depth(-4) == "1")
        #expect(depth(2) == "2")
        #expect(depth(9) == "3")
        #expect(BrainGraphRequest(depth: 9).depth == 3)
        var request = BrainGraphRequest()
        request.depth = 12
        #expect(request.depth == 3)
    }

    @Test func encodesFocusLikeUrlSearchParams() {
        // ':' and ' ' and non-ASCII must match the web byte for byte.
        let query = BrainGraphRequest(focus: "tag:go lang/é").query
        #expect(query.contains("focus=tag%3Ago+lang%2F%C3%A9&depth=1"))
    }

    @Test func emptyFocusIsUnfocused() {
        #expect(BrainGraphRequest(focus: "").query == BrainGraphRequest().query)
    }

    @Test func endpointUsesTheQueryAndNeverPresentsThePaywall() {
        let request = BrainGraphRequest(focus: "ABC")
        let endpoint = BrainGraphEndpoints.Graph(request: request)
        #expect(endpoint.path == request.query)
        #expect(endpoint.presentsPaywallOn402 == false)
    }
}
