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
    ///
    /// When `artboardName` is supplied the named artboard is selected (several
    /// marks live as separate artboards inside one bundled `.riv`); otherwise
    /// the file's default artboard is used. Returns nil — so callers keep their
    /// static-PNG fallback — when the file, artboard, or state machine is
    /// absent, instead of trapping on the runtime's `try!` initializers.
    static func viewModel(
        named name: String,
        artboardName: String? = nil,
        stateMachineName: String
    ) -> RiveViewModel? {
        guard let file = file(named: name) else { return nil }
        let model = RiveModel(riveFile: file)
        do {
            if let artboardName {
                try model.setArtboard(artboardName)
            } else {
                try model.setArtboard()
            }
            try model.setStateMachine(stateMachineName)
        } catch {
            return nil
        }
        return RiveViewModel(model, stateMachineName: stateMachineName, artboardName: artboardName)
    }
}
