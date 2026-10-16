// LuminaVaultClient/LuminaVaultClient/Features/Recap/Period/PeriodRecapStoryView.swift
//
// The year / month in review, played full screen like a story: segmented
// progress along the top, tap the right side for the next card and the left
// for the previous, hold to pause, drag down to close. VoiceOver turns
// auto-advance off and offers Next / Previous actions instead.

import LuminaVaultShared
import SwiftUI

struct PeriodRecapStoryView: View {
    @State private var model: PeriodRecapPlayerModel
    @State private var sharePayload: PeriodRecapSharePayload?
    @State private var dragOffset: CGFloat = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PeriodRecapPlayerModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            StoryBackground(kind: model.current, animates: !reduceMotion)
            content
        }
        .offset(y: dragOffset)
        .scaleEffect(1 - min(dragOffset, 300) / 3000)
        .gesture(dismissDrag)
        .statusBarHidden()
        .task(id: model.request) { await model.load() }
        .task(id: voiceOver) { await advance() }
        .sensoryFeedback(.selection, trigger: model.index)
        .sheet(item: $sharePayload) { payload in
            TodayShareSheet(activityItems: payload.activityItems)
                .presentationDetents([.medium, .large])
                .onDisappear { model.setPaused(false) }
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(palette.textPrimary)
                .overlay(alignment: .top) { topBar(showsProgress: false) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading your recap")
        case let .failed(message):
            messageView(message, action: ("Try again", { Task { await model.load() } }))
        case let .unavailable(recap):
            messageView(PeriodRecapDeck.unavailableText(recap), action: previousAction(for: recap))
        case let .ready(recap):
            deck(recap)
        }
    }

    private func deck(_ recap: PeriodRecapResponse) -> some View {
        ZStack(alignment: .top) {
            if let kind = model.current {
                PeriodRecapCardView(
                    recap: recap,
                    kind: kind,
                    onShare: { share(recap) },
                    onReplay: { model.restart() }
                )
                // A fresh identity per card, so each plays its entrance.
                .id(model.index)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Card \(model.index + 1) of \(model.cards.count)")
                .accessibilityAction(named: "Next") { model.next() }
                .accessibilityAction(named: "Previous") { model.previous() }
            }
            if model.current != .summary {
                tapZones
            }
            topBar(showsProgress: true)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : LVMotion.standard, value: model.index)
    }

    // MARK: - Chrome

    private func topBar(showsProgress: Bool) -> some View {
        VStack(spacing: LVSpacing.sm) {
            if showsProgress {
                HStack(spacing: 4) {
                    ForEach(model.cards.indices, id: \.self) { i in
                        Capsule()
                            .fill(palette.textPrimary.opacity(0.25))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(palette.textPrimary)
                                        .frame(width: proxy.size.width * model.segmentProgress(i))
                                }
                            }
                            .frame(height: 3)
                    }
                }
                .accessibilityHidden(true)
            }
            HStack {
                periodMenu
                Spacer()
                if showsProgress {
                    Button {
                        model.setPaused(!model.isPaused)
                    } label: {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                            .frame(width: LVSize.tapTarget, height: LVSize.tapTarget)
                    }
                    .accessibilityLabel(model.isPaused ? "Play" : "Pause")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: LVSize.tapTarget, height: LVSize.tapTarget)
                }
                .accessibilityLabel("Close recap")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.top, LVSpacing.sm)
    }

    private var periodMenu: some View {
        let now = PeriodRecapRequest.current(.month)
        let thisYear = PeriodRecapRequest.year(now.year)
        let lastYear = PeriodRecapRequest.year(now.year - 1)
        let lastMonth = (now.month ?? 1) == 1
            ? PeriodRecapRequest.month(12, of: now.year - 1)
            : PeriodRecapRequest.month((now.month ?? 1) - 1, of: now.year)
        return Menu {
            ForEach([thisYear, lastYear, now, lastMonth], id: \.self) { option in
                Button(PeriodRecapDeck.periodName(period: option.period, year: option.year, month: option.month)) {
                    Task { await model.select(option) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(PeriodRecapDeck.periodName(
                    period: model.request.period,
                    year: model.request.year,
                    month: model.request.month
                ))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .lvFont(.bodyEmphasis)
        }
        .accessibilityLabel("Choose a recap period")
    }

    /// Left 30% back, the rest forward; a hold pauses.
    private var tapZones: some View {
        HStack(spacing: 0) {
            zone(width: 0.3) { model.previous() }
            zone(width: 0.7) { model.next() }
        }
        .padding(.top, 72)
        .accessibilityHidden(true)
    }

    private func zone(width: CGFloat, action: @escaping () -> Void) -> some View {
        GeometryReader { _ in Color.clear }
            .containerRelativeFrame(.horizontal) { length, _ in length * width }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 30) {} onPressingChanged: { pressing in
                model.setPaused(pressing)
            }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
                model.setPaused(true)
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(LVMotion.snap) { dragOffset = 0 }
                    model.setPaused(false)
                }
            }
    }

    private func messageView(_ text: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.lg) {
            Spacer()
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(palette.primary)
            }
            Spacer()
        }
        .padding(.horizontal, LVSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { topBar(showsProgress: false) }
    }

    private func previousAction(for recap: PeriodRecapResponse) -> (String, () -> Void)? {
        guard recap.unavailableReason != .beforeAccount else { return nil }
        let previous: PeriodRecapRequest = if recap.period == .year {
            .year(recap.year - 1)
        } else if (recap.month ?? 1) == 1 {
            .month(12, of: recap.year - 1)
        } else {
            .month((recap.month ?? 1) - 1, of: recap.year)
        }
        let name = PeriodRecapDeck.periodName(period: previous.period, year: previous.year, month: previous.month)
        return ("See \(name)", { Task { await model.select(previous) } })
    }

    // MARK: - Time

    /// Ticks the deck while the view is up. Off under VoiceOver: a card
    /// should not move on while it is being read.
    private func advance() async {
        guard !voiceOver else { return }
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            let now = clock.now
            let step = (now - last).components
            last = now
            model.tick(Double(step.seconds) + Double(step.attoseconds) / 1e18)
        }
    }

    private func share(_ recap: PeriodRecapResponse) {
        model.setPaused(true)
        var items: [Any] = []
        if let image = PeriodRecapShareCard.render(recap, palette: palette) { items.append(image) }
        items.append(recap.shareText)
        sharePayload = PeriodRecapSharePayload(activityItems: items)
        model.recordShare()
    }
}

private struct PeriodRecapSharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

/// A slow mesh of the palette that shifts hue per card.
private struct StoryBackground: View {
    let kind: RecapCardKind?
    let animates: Bool

    @Environment(\.lvPalette) private var palette
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotion

    var body: some View {
        let (a, b) = hues
        TimelineView(.animation(paused: !animates || !ambientMotion)) { timeline in
            let t = animates && ambientMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            let drift = Float(sin(t / 4) * 0.12)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.5 - drift], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    a.opacity(0.55), palette.backgroundBase, b.opacity(0.4),
                    palette.backgroundBase, a.opacity(0.25), palette.backgroundBase,
                    b.opacity(0.45), palette.backgroundBase, a.opacity(0.35),
                ]
            )
        }
        .background(palette.backgroundBase)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: kind)
        .accessibilityHidden(true)
    }

    private var hues: (Color, Color) {
        switch kind {
        case .captures, .chats: (palette.primary, palette.accent)
        case .rhythm, .themes: (palette.secondary, palette.primary)
        case .streak, .achievements: (palette.accent, palette.secondary)
        default: (palette.primary, palette.secondary)
        }
    }
}
