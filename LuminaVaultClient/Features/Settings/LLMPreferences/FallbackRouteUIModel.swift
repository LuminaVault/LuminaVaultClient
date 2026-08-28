// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/FallbackRouteUIModel.swift
//
// UI-only companion to `ModelRouteDTO` (LuminaVaultShared). Per the repo's
// DTO rule the wire type stays exactly as the server defines it — a plain
// `(provider, model)` pair whose only identity is its position in the array.
// That is right for the wire, where the chain's meaning *is* positional, and
// wrong for an editor, where the user reorders and deletes rows.
//
// Why this type exists
// ====================
// The fallback editor carries both `.onDelete` and `.onMove`. It used to key
// its `ForEach` on the enumeration offset, which makes SwiftUI treat "the row
// at index 2" as the same row before and after a move or a delete. The row
// view — including a live `TextField` with focus and an uncommitted text
// buffer — is therefore reused while the route underneath it slides away, and
// the pending edit commits into whichever route now occupies that offset. On
// a screen whose whole job is deciding which model your money and your
// prompts go to, that is a data-corruption path, not a rendering nit.
//
// Giving each row a `UUID` makes identity follow the route through a reorder,
// so SwiftUI tears down and rebuilds the right rows and every edit lands on
// the step the user was pointing at.
//
// Why the id does not round-trip
// ==============================
// `ModelRouteDTO` has no id field and the client does not author DTOs, so
// there is nothing to persist and nothing to derive an id from: two steps in
// a chain may legitimately be byte-identical (the same model listed twice as
// a retry), which rules out a content hash — it would mint duplicate ids for
// exactly the rows that most need distinguishing. A fresh `UUID` is minted
// every time a server snapshot is applied. That is sufficient, because the
// window identity has to survive is a single editing session: load, reorder,
// delete, edit, save. A save replaces the whole chain from the server's
// response anyway.

import Foundation
import LuminaVaultShared

/// One editable step in the user's model fallback chain.
struct FallbackRouteUIModel: Identifiable, Equatable, Sendable {
    let id: UUID
    var provider: ProviderID
    var model: String

    init(id: UUID = UUID(), provider: ProviderID, model: String) {
        self.id = id
        self.provider = provider
        self.model = model
    }

    init(id: UUID = UUID(), route: ModelRouteDTO) {
        self.init(id: id, provider: route.provider, model: route.model)
    }

    /// The wire representation of this step. Order comes from the array.
    var route: ModelRouteDTO {
        ModelRouteDTO(provider: provider, model: model)
    }

    /// Wraps a server snapshot into editable rows, minting a fresh id each.
    static func rows(from routes: [ModelRouteDTO]) -> [FallbackRouteUIModel] {
        routes.map { FallbackRouteUIModel(route: $0) }
    }
}
