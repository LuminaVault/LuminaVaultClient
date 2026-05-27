// LuminaVaultClient/LuminaVaultClient/Features/KB/ConfettiOverlay.swift
// HER-108 — lightweight emoji confetti for the "Sync & Learn" completion
// moment. Custom SwiftUI in lieu of a third-party SPM dep — keeps the
// pbxproj clean and matches the mascot's hand-drawn vibe.
import SwiftUI

struct ConfettiOverlay: View {
    /// Bumping this triggers a new emission. Use `vm.confettiTrigger` as the binding.
    let trigger: Int

    var body: some View {
        ConfettiBurst(seed: trigger)
            .id(trigger) // forces re-mount per trigger
            .allowsHitTesting(false)
    }
}

private struct ConfettiBurst: View {
    let seed: Int

    private static let emojis = ["✨", "🎉", "🪄", "💡", "📚", "🌟"]
    private static let count = 32

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0 ..< Self.count, id: \.self) { i in
                    ConfettiPiece(
                        emoji: Self.emojis[(i + seed) % Self.emojis.count],
                        xOffset: deterministicRandom(seed: seed * 31 + i, lo: 0, hi: proxy.size.width),
                        delay: deterministicRandom(seed: seed * 47 + i, lo: 0, hi: 0.4),
                        rotation: deterministicRandom(seed: seed * 53 + i, lo: -180, hi: 180),
                        screenHeight: proxy.size.height,
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Mulberry-style deterministic shuffle so each `seed` looks varied but
    /// stable across re-renders. Avoids hooking SystemRandomNumberGenerator.
    private func deterministicRandom(seed: Int, lo: Double, hi: Double) -> Double {
        var x = UInt64(bitPattern: Int64(seed &* 2_654_435_761))
        x ^= x &>> 33
        x &*= 0xff51_afd7_ed55_8ccd
        x ^= x &>> 33
        let unit = Double(x & 0xFFFF_FFFF) / Double(UInt32.max)
        return lo + (hi - lo) * unit
    }
}

private struct ConfettiPiece: View {
    let emoji: String
    let xOffset: Double
    let delay: Double
    let rotation: Double
    let screenHeight: Double

    @State private var animate = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 22))
            .position(
                x: xOffset,
                y: animate ? screenHeight + 40 : -40,
            )
            .rotationEffect(.degrees(animate ? rotation * 2 : 0))
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 1.8).delay(delay)) {
                    animate = true
                }
            }
    }
}
