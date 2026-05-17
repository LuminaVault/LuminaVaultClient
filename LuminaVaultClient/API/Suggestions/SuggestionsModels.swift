// LuminaVaultClient/LuminaVaultClient/API/Suggestions/SuggestionsModels.swift
// HER-37: re-exports LuminaVaultShared.SuggestionsResponse so the rest of
// the client can refer to it bare.
import Foundation
@_exported import LuminaVaultShared

typealias SuggestionsResponse = LuminaVaultShared.SuggestionsResponse
