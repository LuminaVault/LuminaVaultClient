// LuminaVaultClient/LuminaVaultClient/Features/QuickAssistant/AITabHitTest.swift
//
// Which part of the tab bar counts as the AI tab. The items are not reachable
// through public API, so this is arithmetic. Measured on iOS 26.2:
//
//  * Portrait, 402pt bar: 77pt items, AI at 162.5-239.5.
//  * Landscape, 874pt bar: items sized to their labels and centred, AI at
//    404.7-470.7. The middle fifth of this bar runs 349.8-524.2, across half of
//    Spaces and Brain, so the slot alone would fire on the neighbours.
//  * Minimized: one 48pt pill at x=28 showing the current tab, which lands in the
//    first slot, so a press there is deliberately not a trigger.
//
// So a press must be in the AI slot and within one item's reach of its centre.
// AI is the middle tab, so its centre is the bar's in every layout above.
import CoreGraphics

enum AITabHitTest {
    /// Half the 77pt item measured in portrait.
    private static let maxItemHalfWidth: CGFloat = 38.5

    static func isAITab(x: CGFloat, barWidth: CGFloat, tabCount: Int, aiIndex: Int) -> Bool {
        guard x.isFinite, barWidth.isFinite, barWidth > 0, tabCount > 0, x >= 0, x < barWidth else {
            return false
        }
        let slotWidth = barWidth / CGFloat(tabCount)
        let slotCentre = (CGFloat(aiIndex) + 0.5) * slotWidth
        return Int(x / slotWidth) == aiIndex && abs(x - slotCentre) <= maxItemHalfWidth
    }
}
