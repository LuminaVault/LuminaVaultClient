// LuminaVaultClient/LuminaVaultClient/API/Spaces/SpacesEndpoints.swift
// HER-35: CRUD for user-defined organizing folders. All endpoints
// authenticated; server tenant is inferred from the JWT.
import Foundation

enum SpacesEndpoints {
    struct List: Endpoint {
        typealias Response = SpaceListResponse
        var path: String { "/v1/spaces" }
        var method: HTTPMethod { .get }
    }

    struct GetOne: Endpoint {
        typealias Response = SpaceDTO
        let id: UUID
        var path: String { "/v1/spaces/\(id.uuidString)" }
        var method: HTTPMethod { .get }
    }

    struct Create: Endpoint {
        typealias Response = SpaceDTO
        let request: CreateSpaceRequest
        var path: String { "/v1/spaces" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = SpaceDTO
        let id: UUID
        let request: UpdateSpaceRequest
        var path: String { "/v1/spaces/\(id.uuidString)" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/spaces/\(id.uuidString)" }
        var method: HTTPMethod { .delete }
    }
}
