// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceIcon.swift
// One place that knows which icons a space can have and how a stored icon
// name becomes a glyph. The card and the editor's icon grid both read it, so
// what the user picks is what the card shows.
import Foundation

enum SpaceIcon {
    /// An icon the editor offers. `symbol` is what the server stores;
    /// `label` is what VoiceOver reads — the symbol name is never shown.
    struct Choice: Identifiable, Equatable {
        let symbol: String
        let label: String
        var id: String { symbol }
    }

    static let defaultSymbol = "folder.fill"

    /// Every choice resolves to a different glyph (see `SpaceIconTests`).
    static let choices: [Choice] = [
        Choice(symbol: "folder.fill", label: "Folder"),
        Choice(symbol: "sparkles", label: "Sparkles"),
        Choice(symbol: "chart.line.uptrend.xyaxis", label: "Chart"),
        Choice(symbol: "heart.fill", label: "Heart"),
        Choice(symbol: "briefcase.fill", label: "Briefcase"),
        Choice(symbol: "lightbulb.fill", label: "Lightbulb"),
        Choice(symbol: "brain.head.profile", label: "Brain"),
        Choice(symbol: "camera.fill", label: "Camera"),
        Choice(symbol: "house.fill", label: "Home"),
        Choice(symbol: "wand.and.stars", label: "Magic wand"),
        Choice(symbol: "music.note", label: "Music"),
        Choice(symbol: "globe", label: "Globe"),
    ]

    static func isChoice(_ symbol: String?) -> Bool {
        guard let symbol else { return false }
        return choices.contains { $0.symbol == symbol }
    }

    /// HER-307 — the server returns an SF Symbol name (or nil). Map common
    /// values to `LVIcon` cases so cards pick up the branded glyph.
    /// Unknown / unset icons fall back to `.scrollWinged`, which draws the
    /// plain scroll symbol: winged art reads as a second logo here.
    static func resolve(_ raw: String?) -> LVIcon {
        switch raw {
        case "brain.head.profile", "brain":     return .brainHeadProfile
        case "heart.fill", "heart":             return .heartWinged
        case "lightbulb.fill", "lightbulb":     return .lightbulbFill
        case "chart.line.uptrend.xyaxis",
             "chart.xyaxis.line":               return .chartUp
        case "briefcase.fill", "briefcase":     return .briefcase
        case "lock.shield.fill", "lock.shield": return .shieldBrain
        case "doc.text.fill", "doc.text",
             "scroll.fill", "scroll":           return .scrollWinged
        case "folder.fill", "folder":           return .layers
        case "house.fill", "house":             return .homeGlow
        case "camera.aperture", "camera.fill",
             "camera":                          return .cameraAperture
        case "mic.fill", "mic":                 return .micFill
        case "link", "link.circle":             return .linkCircle
        case "wand.and.stars":                  return .wandSparkle
        case "key.fill", "key":                 return .skeletonKeyPremium
        case "sparkles":                        return .sparkles
        case "globe":                           return .globe
        case "music.note":                      return .musicNote
        case "book.fill", "book":               return .bookmarkFill
        default:                                return .scrollWinged
        }
    }
}
