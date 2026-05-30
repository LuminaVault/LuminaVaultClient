// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/VoiceWaveformView.swift
//
// Inline gold waveform shown in the composer while hold-to-talk is
// recording. Lightweight `Canvas` (no per-bar subviews) driven by a
// `TimelineView`; pauses + flattens under Reduce Motion.
import SwiftUI

struct VoiceWaveformView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool

    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let slot = size.width / CGFloat(barCount)
                let barWidth = slot * 0.5
                for index in 0 ..< barCount {
                    let phase = Double(index) * 0.7
                    let amplitude = reduceMotion
                        ? 0.5
                        : 0.35 + 0.65 * abs(sin(now * 6 + phase))
                    let height = max(barWidth, size.height * CGFloat(amplitude))
                    let x = CGFloat(index) * slot + (slot - barWidth) / 2
                    let rect = CGRect(x: x, y: (size.height - height) / 2,
                                      width: barWidth, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(palette.accent)
                    )
                }
            }
        }
        .frame(width: 44, height: 22)
        .accessibilityHidden(true)
    }
}
