// LuminaVaultClient/LuminaVaultClient/Utilities/LVGlow.swift
import CoreGraphics

/// Named glow / glass intensities so screen code stops hardcoding floats.
/// All values are 0...1 and feed `lvGlassCard(intensity:)`, `lvGlowStroke(intensity:)`,
/// `lvInnerGlow(intensity:)`, and any palette-tinted `.shadow` opacity.
enum LVGlow {
    static let hero: CGFloat = 0.45
    static let card: CGFloat = 0.5
    static let subtle: CGFloat = 0.3
    static let focused: CGFloat = 0.7
    static let max: CGFloat = 0.9
}
