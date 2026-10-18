// LuminaVaultShareExtension/ShareExtensionConfig.swift
//
// Kept as the share extension's name for `ExtensionAPIConfig`, which the
// widget extension reads too.

import Foundation

nonisolated enum ShareExtensionConfig {
    static var apiBaseURL: URL {
        ExtensionAPIConfig.apiBaseURL
    }

    static var keychainAccessGroup: String? {
        ExtensionAPIConfig.keychainAccessGroup
    }
}
