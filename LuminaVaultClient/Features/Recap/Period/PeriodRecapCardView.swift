// LuminaVaultClient/LuminaVaultClient/Features/Recap/Period/PeriodRecapCardView.swift
//
// One card of the year / month in review. Each card plays its entrance once
// when it appears (the player gives every card a fresh identity), and with
// Reduce Motion on it simply shows its final state.

import LuminaVaultShared
import SwiftUI

struct PeriodRecapCardView: View {
    let recap: PeriodRecapResponse
    let kind: RecapCardKind
    var onShare: () -> Void = {}
    var onReplay: () -> Void = {}

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Snapshot tests turn this off to render the settled card.
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotion
    @State private var appeared = false

    private var animates: Bool {
        !reduceMotion && ambientMotion
    }

    private var span: String {
        recap.period == .month ? "month" : "year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.lg) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, LVSpacing.xl)
        .padding(.top, 88)
        .padding(.bottom, LVSpacing.xxl)
        .foregroundStyle(palette.textPrimary)
        .onAppear {
            guard animates else {
                appeared = true
                return
            }
            withAnimation(LVMotion.gentle) { appeared = true }
        }
    }

    // MARK: - Cards

    @ViewBuilder private var content: some View {
        switch kind {
        case .intro:
            Spacer()
            eyebrow("Your")
            display(PeriodRecapDeck.periodName(recap))
                .entrance(appeared, delay: 0.1, animates: animates, scale: 0.7)
            lead(recap.isComplete ? "in review" : "so far")
                .entrance(appeared, delay: 0.4, animates: animates)
            HermieMascotView(state: .celebrating, size: 96, animated: animates)
                .entrance(appeared, delay: 0.7, animates: animates, scale: 0.4)
            Text("Tap to continue · hold to pause")
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
                .entrance(appeared, delay: 0.9, animates: animates)
            Spacer()
        case .captures:
            if let card = recap.captures {
                Spacer()
                eyebrow("This \(span) you kept")
                bigNumber(PeriodRecapDeck.memories(recap))
                lead("memories")
                body("\(card.captures) you saved, \(card.learned) Lumina learned for you.")
                if let delta = PeriodRecapDeck.delta(
                    PeriodRecapDeck.memories(recap),
                    previous: card.previousCaptures + card.previousLearned
                ) {
                    chip("\(delta) on the \(span) before")
                }
                bars(card.series.map(\.count), height: 110)
                Spacer()
            }
        case .peak:
            if let card = recap.peak {
                Spacer()
                eyebrow("Your busiest \(span == "year" ? "month" : "day")")
                display(PeriodRecapDeck.bucketName(card.busiest.key))
                    .entrance(appeared, delay: 0.1, animates: animates, scale: 0.7)
                body("\(card.busiest.count) memories in one \(span == "year" ? "month" : "day").")
                weekdayBars(card)
                lead("\(PeriodRecapDeck.weekdayName(card.busiestWeekday))s were your day.")
                    .entrance(appeared, delay: 1.1, animates: animates)
                Spacer()
            }
        case .rhythm:
            if let card = recap.rhythm {
                let persona = PeriodRecapDeck.persona(card.persona)
                Spacer()
                eyebrow("You're")
                display(persona.title)
                    .entrance(appeared, delay: 0.1, animates: animates, scale: 0.7)
                body(persona.line)
                HourClock(counts: card.hourCounts, peakHour: card.peakHour, progress: appeared ? 1 : 0)
                    .frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity)
                    .animation(animates ? .easeOut(duration: 1.2).delay(0.3) : nil, value: appeared)
                lead("Peak hour: \(PeriodRecapDeck.hourLabel(card.peakHour))")
                    .entrance(appeared, delay: 0.9, animates: animates)
                Spacer()
            }
        case .topics:
            if let card = recap.topics {
                Spacer()
                eyebrow("You kept coming back to")
                FlowTags(tags: card.topTags, appeared: appeared, animates: animates)
                if let space = card.topSpace {
                    body("Most of it lived in \(space.label).")
                        .entrance(appeared, delay: 0.9, animates: animates)
                }
                Spacer()
            }
        case .chats:
            if let card = recap.chats {
                Spacer()
                eyebrow("You asked Lumina")
                bigNumber(card.messagesSent)
                lead("questions")
                body("across \(card.conversations) \(card.conversations == 1 ? "conversation" : "conversations").")
                if let delta = PeriodRecapDeck.delta(card.messagesSent, previous: card.previousMessagesSent) {
                    chip("\(delta) on the \(span) before")
                }
                Spacer()
            }
        case .skills:
            if let card = recap.skills {
                Spacer()
                eyebrow("Your agents went to work")
                bigNumber(card.runs)
                lead("runs")
                if let top = card.topSkill {
                    body("Your favourite: \(top.label), \(top.count) times.")
                }
                Spacer()
            }
        case .streak:
            if let card = recap.streak {
                Spacer()
                eyebrow("Your longest streak")
                HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
                    bigNumber(card.longestDays)
                    Flame(animates: animates)
                }
                lead("\(card.longestDays == 1 ? "day" : "days") in a row")
                if let start = card.longestStart, let end = card.longestEnd, card.longestDays > 1 {
                    body("\(PeriodRecapDeck.bucketName(start)) to \(PeriodRecapDeck.bucketName(end)).")
                }
                meter(card.totalDays == 0 ? 0 : Double(card.activeDays) / Double(card.totalDays))
                body("You showed up on \(card.activeDays) of \(card.totalDays) days.")
                Spacer()
            }
        case .achievements:
            if let card = recap.achievements {
                Spacer()
                eyebrow("You unlocked")
                bigNumber(card.unlocked)
                lead(card.unlocked == 1 ? "badge" : "badges")
                ForEach(Array(card.items.enumerated()), id: \.element.id) { i, item in
                    Label(item.title, systemImage: "rosette")
                        .lvFont(.bodyEmphasis)
                        .entrance(appeared, delay: 0.5 + Double(i) * 0.12, animates: animates)
                }
                Spacer()
            }
        case .themes:
            let text = PeriodRecapDeck.themes(recap)
            Spacer()
            eyebrow("Your \(span) in a sentence")
            if let headline = text.headline {
                display(headline, size: 44)
                    .entrance(appeared, delay: 0.1, animates: animates, scale: 0.7)
            }
            WordReveal(sentence: text.sentence, appeared: appeared, animates: animates)
            if recap.themes?.status == .ready, let themes = recap.themes?.themes, !themes.isEmpty {
                HStack(spacing: LVSpacing.sm) {
                    ForEach(themes, id: \.self) { theme in chip(theme, delay: 1.6) }
                }
            }
            Spacer()
        case .summary:
            summary
        case .unknown:
            EmptyView()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: LVSpacing.lg) {
            Spacer()
            eyebrow(recap.isComplete ? "My \(span) in review" : "My \(span) so far")
            display(PeriodRecapDeck.periodName(recap), size: 52)
                .entrance(appeared, delay: 0.1, animates: animates, scale: 0.8)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: LVSpacing.lg) {
                ForEach(Array(PeriodRecapDeck.shareStats(recap).enumerated()), id: \.offset) { i, stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.label.uppercased())
                            .lvFont(.microTag)
                            .foregroundStyle(palette.textSecondary)
                        Text(stat.value)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(i == 0 ? palette.primary : palette.textPrimary)
                    }
                    .entrance(appeared, delay: 0.3 + Double(i) * 0.09, animates: animates)
                }
            }
            lead(PeriodRecapDeck.persona(recap.rhythm?.persona).title)
                .foregroundStyle(palette.accent)
                .entrance(appeared, delay: 0.9, animates: animates)
            HStack(spacing: LVSpacing.md) {
                Button(action: onShare) {
                    Label("Share image", systemImage: "square.and.arrow.up")
                        .lvFont(.bodyEmphasis)
                        .padding(.horizontal, LVSpacing.base)
                        .frame(minHeight: LVSize.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(palette.primary)
                .accessibilityHint("Shares an image of your numbers. No titles, tags or themes are included.")
                Button("Replay", action: onReplay)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(palette.textPrimary)
            }
            .entrance(appeared, delay: 1.0, animates: animates)
            Spacer()
        }
    }

    // MARK: - Pieces

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .lvFont(.fieldLabel)
            .tracking(1.2)
            .foregroundStyle(palette.textSecondary)
            .entrance(appeared, delay: 0, animates: animates)
    }

    private func display(_ text: String, size: CGFloat = 64) -> some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(2)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .entrance(appeared, delay: 0.3, animates: animates)
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .lvFont(.body)
            .foregroundStyle(palette.textSecondary)
            .entrance(appeared, delay: 0.45, animates: animates)
    }

    private func chip(_ text: String, delay: Double = 0.6) -> some View {
        Text(text)
            .lvFont(.bodyEmphasis)
            .padding(.horizontal, LVSpacing.md)
            .padding(.vertical, LVSpacing.xs)
            .background(Capsule().fill(palette.surface))
            .overlay(Capsule().stroke(palette.surfaceStroke))
            .entrance(appeared, delay: delay, animates: animates)
    }

    private func bigNumber(_ value: Int) -> some View {
        Text((appeared ? value : 0).formatted())
            .font(.system(size: 96, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.primary)
            .shadow(color: palette.glowPrimary.opacity(0.5), radius: 24)
            .contentTransition(.numericText(value: Double(appeared ? value : 0)))
            .animation(animates ? .easeOut(duration: 1.3).delay(0.2) : nil, value: appeared)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel(value.formatted())
    }

    private func bars(_ counts: [Int], height: CGFloat) -> some View {
        let heights = PeriodRecapDeck.normalised(counts)
        let step = counts.count > 12 ? 0.02 : 0.06
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, value in
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .bottom, endPoint: .top))
                    .frame(height: max(3, height * value))
                    .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                    .animation(animates ? LVMotion.snap.delay(0.5 + Double(i) * step) : nil, value: appeared)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func weekdayBars(_ card: RecapPeakCardDTO) -> some View {
        let heights = PeriodRecapDeck.normalised(card.weekdayCounts)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return HStack(alignment: .bottom, spacing: LVSpacing.sm) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, value in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(i + 1 == card.busiestWeekday ? palette.accent : palette.primary)
                        .frame(height: max(4, 110 * value))
                        .scaleEffect(y: appeared ? 1 : 0, anchor: .bottom)
                        .animation(animates ? LVMotion.snap.delay(0.5 + Double(i) * 0.08) : nil, value: appeared)
                    Text(letters[i])
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(height: 130, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func meter(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(palette.surface)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.accent, palette.primary], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * (appeared ? fraction : 0))
                        .animation(animates ? .easeOut(duration: 1).delay(0.7) : nil, value: appeared)
                }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Entrance

private struct Entrance: ViewModifier {
    let appeared: Bool
    let delay: Double
    let animates: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || scale != 1 ? 0 : 18)
            .scaleEffect(appeared ? 1 : scale)
            .animation(animates ? LVMotion.standardSpring.delay(delay) : nil, value: appeared)
    }
}

private extension View {
    func entrance(_ appeared: Bool, delay: Double, animates: Bool, scale: CGFloat = 1) -> some View {
        modifier(Entrance(appeared: appeared, delay: delay, animates: animates, scale: scale))
    }
}

// MARK: - Parts

/// Twenty-four rays around a dial, hour 0 at the top. `progress` grows them.
private struct HourClock: View, Animatable {
    let counts: [Int]
    let peakHour: Int
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
        .accessibilityHidden(true)
    }

    private func point(_ center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let inner: CGFloat = side * 0.26
        let reach: CGFloat = side * 0.22
        let dial = CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)
        context.stroke(Path(ellipseIn: dial), with: .color(palette.surfaceStroke), lineWidth: 1.5)
        let heights = PeriodRecapDeck.normalised(counts)
        for (hour, height) in heights.enumerated() {
            let angle: Double = Double(hour) / 24 * 2 * Double.pi - Double.pi / 2
            let length: CGFloat = inner + 6 + reach * CGFloat(height * progress)
            var ray = Path()
            ray.move(to: point(center, angle: angle, radius: inner + 6))
            ray.addLine(to: point(center, angle: angle, radius: length))
            let color = hour == peakHour ? palette.accent : palette.primary
            context.stroke(ray, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

/// Tags pop in one after another, biggest first.
private struct FlowTags: View {
    let tags: [RecapCountDTO]
    let appeared: Bool
    let animates: Bool

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { i, tag in
                HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
                    Text("#\(tag.label)")
                        .font(.system(size: max(22, 40 - CGFloat(i) * 4), weight: .heavy, design: .rounded))
                    Text("\(tag.count)")
                        .lvFont(.callout)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, LVSpacing.md)
                .padding(.vertical, LVSpacing.xs)
                .background(Capsule().fill(palette.surface))
                .scaleEffect(appeared ? 1 : 0.4, anchor: .leading)
                .opacity(appeared ? 1 : 0)
                .animation(animates ? LVMotion.snap.delay(0.15 + Double(i) * 0.14) : nil, value: appeared)
            }
        }
    }
}

/// The sentence arrives a word at a time.
private struct WordReveal: View {
    let sentence: String
    let appeared: Bool
    let animates: Bool

    var body: some View {
        let words = sentence.split(separator: " ").map(String.init)
        // `Text` concatenation keeps natural wrapping while each word fades.
        words.enumerated().reduce(Text("")) { text, item in
            let (i, word) = item
            let shown = !animates || appeared && i < revealed
            return text + Text(word + " ").foregroundStyle(shown ? Color.primary : Color.clear)
        }
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .task(id: appeared) {
            guard animates, appeared else { return }
            revealed = 0
            try? await Task.sleep(for: .milliseconds(400))
            for i in 1 ... max(1, words.count) {
                withAnimation(.easeOut(duration: 0.2)) { revealed = i }
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
        .accessibilityLabel(sentence)
    }

    @State private var revealed = 0
}

/// A flame that flickers with a keyframe loop.
private struct Flame: View {
    let animates: Bool
    @Environment(\.lvPalette) private var palette

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 56))
            .foregroundStyle(LinearGradient(colors: [palette.accent, .red], startPoint: .top, endPoint: .bottom))
            .keyframeAnimator(initialValue: 1.0, repeating: animates) { content, scale in
                content.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                SpringKeyframe(1.12, duration: 0.35)
                SpringKeyframe(0.94, duration: 0.3)
                SpringKeyframe(1.0, duration: 0.35)
            }
            .accessibilityHidden(true)
    }
}
