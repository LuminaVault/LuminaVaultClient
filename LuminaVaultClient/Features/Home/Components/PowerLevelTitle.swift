// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/PowerLevelTitle.swift
//
// Milestone "rank" titles for the Home Power Level ring. A pure function of
// the server-derived `powerLevel`, so it needs no wire-format change — the
// flavor lives entirely client-side.

import Foundation

enum PowerLevelTitle {
    /// Sci-fi rank for a given power level. Bands widen as levels slow down
    /// (the server's floor(√xp)+1 curve), so each title lasts a meaningful
    /// stretch of progress.
    static func title(for level: Int) -> String {
        switch level {
        case ..<10: return "Spark"
        case ..<50: return "Synapse"
        case ..<100: return "Cortex"
        case ..<250: return "Neural Awakening"
        case ..<500: return "Mind Forge"
        default: return "Singularity"
        }
    }
}
