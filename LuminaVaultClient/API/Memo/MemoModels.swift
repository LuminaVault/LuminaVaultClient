// LuminaVaultClient/LuminaVaultClient/API/Memo/MemoModels.swift
// HER-37: re-exports the LuminaVaultShared memo DTOs and attaches the
// retroactive SwiftUI-friendly conformances. Shared keeps its wire types
// free of Identifiable / Equatable so we add them here.
import Foundation
@_exported import LuminaVaultShared

typealias MemoRequest = LuminaVaultShared.MemoRequest
typealias MemoResponse = LuminaVaultShared.MemoResponse
typealias MemoSummaryDTO = LuminaVaultShared.MemoSummaryDTO
typealias MemoListResponse = LuminaVaultShared.MemoListResponse

extension LuminaVaultShared.MemoSummaryDTO: @retroactive Equatable, @retroactive Identifiable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.path == rhs.path
            && lhs.createdAt == rhs.createdAt
            && lhs.summary == rhs.summary
    }
}

extension LuminaVaultShared.MemoListResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memos == rhs.memos
    }
}

extension LuminaVaultShared.MemoResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memo == rhs.memo
            && lhs.path == rhs.path
            && lhs.sourceMemoryIds == rhs.sourceMemoryIds
            && lhs.summary == rhs.summary
    }
}
