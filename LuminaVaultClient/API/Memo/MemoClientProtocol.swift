// LuminaVaultClient/LuminaVaultClient/API/Memo/MemoClientProtocol.swift
// HER-37: protocol seam so ViewModels (and tests) can stub the network
// layer for the memo generator + memo list endpoints.
import Foundation

protocol MemoClientProtocol: Sendable {
    /// POST /v1/memos — generate a memo (agent loop → markdown synthesis
    /// → vault save). `save == false` returns the memo body without
    /// persisting; defaults to true server-side.
    func generate(_ request: MemoRequest) async throws -> MemoResponse

    /// GET /v1/memos — list memos saved under `memos/<date>/<slug>.md` for
    /// the authenticated tenant. Server returns most-recent first.
    func list() async throws -> MemoListResponse
}
