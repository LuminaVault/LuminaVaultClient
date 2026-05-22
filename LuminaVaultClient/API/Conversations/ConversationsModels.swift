// LuminaVaultClient/LuminaVaultClient/API/Conversations/ConversationsModels.swift
//
// HER-269 — re-export LuminaVaultShared Conversations DTOs as iOS-local
// typealiases (mirrors the pattern in API/Settings/SettingsModels.swift).
// Server contract:
//   POST   /v1/conversations
//   GET    /v1/conversations
//   GET    /v1/conversations/:id
//   DELETE /v1/conversations/:id
//   POST   /v1/conversations/:id/messages/stream  (SSE → QueryStreamEvent)
import Foundation
@_exported import LuminaVaultShared

typealias ConversationDTO = LuminaVaultShared.ConversationDTO
typealias ConversationMessageDTO = LuminaVaultShared.ConversationMessageDTO
typealias ConversationMessageRole = LuminaVaultShared.ConversationMessageRole
typealias ConversationCreateRequest = LuminaVaultShared.ConversationCreateRequest
typealias ConversationListResponse = LuminaVaultShared.ConversationListResponse
typealias ConversationDetailResponse = LuminaVaultShared.ConversationDetailResponse
typealias MessageStreamRequest = LuminaVaultShared.MessageStreamRequest
typealias QueryStreamEvent = LuminaVaultShared.QueryStreamEvent
// QueryHitDTO is aliased in API/Memory/MemoryQueryModels.swift — used
// transitively here via QueryStreamEvent.source(QueryHitDTO).
typealias ProviderFallbackNoticeDTO = LuminaVaultShared.ProviderFallbackNoticeDTO
