// HER-287 — Screen 8: Capture source preference (2-col grid, multi-select).
import SwiftUI

struct CaptureSourcesView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        FunnelScreenChrome(
            headline: "What should flow into your vault?",
            subhead: "Pick what you actually use.",
            primaryCTA: "Continue",
            onPrimary: { state.advance() }
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(FunnelCaptureSource.allCases) { source in
                    Button {
                        state.toggleCaptureSource(source)
                    } label: {
                        tile(for: source)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func tile(for source: FunnelCaptureSource) -> some View {
        let selected = state.selectedCaptureSources.contains(source)
        return VStack(spacing: 8) {
            Text(source.emoji).font(.system(size: 30))
            Text(source.label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(selected ? palette.glowPrimary.opacity(0.15) : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    selected ? palette.glowPrimary : Color.gray.opacity(0.2),
                    lineWidth: selected ? 1.5 : 1
                )
        )
    }
}
