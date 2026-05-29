// HER-287 — Screen 4: Social proof (placeholder testimonials).
import SwiftUI

struct SocialProofView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        FunnelScreenChrome(
            headline: "Researchers, founders, and writers are already moving in.",
            subhead: "Real corpus. Real continuity. Real voice.",
            primaryCTA: "Continue",
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 12) {
                ForEach(FunnelTestimonial.verified) { t in
                    card(for: t)
                }
            }
        }
    }

    private func card(for testimonial: FunnelTestimonial) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(palette.glowPrimary.opacity(0.25))
                        .frame(width: 36, height: 36)
                    Text(testimonial.initials)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.glowPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(testimonial.initials)
                        .font(.system(size: 14, weight: .semibold))
                    Text(testimonial.persona)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(testimonial.quote)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
