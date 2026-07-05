// LuminaVaultClient/LuminaVaultClient/Components/RiveAssets.swift
import Foundation
import RiveRuntime
import SwiftUI

/// Process-wide cache of parsed `.riv` files.
///
/// `RiveViewModel(fileName:)` re-reads and re-parses the binary on every
/// init; hero marks and the mascot can appear many times per screen, so each
/// bundled asset is parsed once here and every view builds its own
/// `RiveModel` on top (artboard/state-machine instance state stays per-view,
/// never shared).
@MainActor
enum RiveAssets {
    private static var files: [String: RiveFile] = [:]

    /// Shared parsed file for a bundled `.riv`, or nil when the asset does
    /// not ship in this build (callers keep their static-PNG fallback).
    static func file(named name: String) -> RiveFile? {
        if let cached = files[name] { return cached }
        guard Bundle.main.url(forResource: name, withExtension: "riv") != nil,
              let file = try? RiveFile(name: name) else { return nil }
        files[name] = file
        return file
    }

    /// Fresh view model bound to its own artboard instance on the shared file.
    static func viewModel(named name: String, stateMachineName: String) -> RiveViewModel? {
        guard let file = file(named: name) else { return nil }
        return RiveViewModel(RiveModel(riveFile: file), stateMachineName: stateMachineName)
    }
}
