// LuminaVaultClient/LuminaVaultClient/Features/Recap/RecapSheet.swift
//
// "Last 7 days" — what you saved, what Lumina learned, what you asked and
// revisited, against the window before; which days you did it on; and the
// few memories worth seeing again. Opened from Home's "Your week" strip.
//
// Sharing sends `RecapShareCard`: numbers and bars, never titles.

import LuminaVaultShared
import SwiftUI
import UIKit

struct RecapSheet: View {
    @State private var vm: RecapViewModel
    /// The picker's own copy of the range; `.task(id:)` hands it to the view
    /// model so a switch is a structured, cancellable load.
    @State private var pickerRange: AnalyticsRange
    @State private var openMemory: RecapMemoryLink?
    @State private var sharePayload: RecapSharePayload?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private let memoryClient: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        viewModel: RecapViewModel,
        memoryClient: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        _pickerRange = State(initialValue: viewModel.range)
        self.memoryClient = memoryClient
        self.spacesClient = spacesClient
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.xl) {
                    Picker("Range", selection: $pickerRange) {
                        Text("7 days").tag(AnalyticsRange.week)
                        Text("30 days").tag(AnalyticsRange.month)
                    }
                    .pickerStyle(.segmented)

                    content
                }
                // Reduced motion drops the cross-fade (see `lvAnimation`).
                .lvAnimation(LVMotion.standard, value: vm.state)
                .padding(.horizontal, LVSpacing.base)
                .padding(.top, LVSpacing.sm)
                .padding(.bottom, LVSpacing.xl)
            }
            .background(palette.backgroundBase)
            .refreshable { await vm.reload() }
            .safeAreaInset(edge: .bottom) { shareBar }
            .navigationTitle(vm.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: pickerRange) {
                if pickerRange == vm.range {
                    await vm.load()
                } else {
                    await vm.select(range: pickerRange)
                }
            }
            .navigationDestination(item: $openMemory) { link in
                MemoryDetailView(memoryID: link.id, client: memoryClient, spacesClient: spacesClient)
            }
            .sheet(item: $sharePayload) { payload in
                TodayShareSheet(activityItems: payload.activityItems)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        switch vm.state {
        case .loading:
            RecapBody(recap: RecapPlaceholder.recap, vm: vm, openMemory: $openMemory)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading your recap")
        case let .failed(message):
            ContentUnavailableView {
                Label(message, systemImage: "chart.bar.xaxis")
            } actions: {
                Button("Try again") { Task { await vm.reload() } }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, LVSpacing.xxl)
        case let .loaded(recap):
            RecapBody(recap: recap, vm: vm, openMemory: $openMemory)
                .transition(.opacity)
        }
    }

    // MARK: - Share

    private var shareBar: some View {
        Button {
            share()
        } label: {
            Label("Share recap", systemImage: "square.and.arrow.up")
                .lvFont(.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: LVSize.buttonHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(palette.primary)
        .disabled(vm.recap == nil)
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.sm)
        .background(.bar)
        .accessibilityHint("Shares an image of your numbers. No titles or contents are included.")
    }

    private func share() {
        guard let recap = vm.recap else { return }
        var items: [Any] = []
        if let image = RecapShareCard.render(recap) { items.append(image) }
        items.append(recap.shareText)
        sharePayload = RecapSharePayload(activityItems: items)
    }
}

// MARK: - Body

/// Everything under the picker, for one loaded (or placeholder) recap.
private struct RecapBody: View {
    let recap: MeRecapResponse
    let vm: RecapViewModel
    @Binding var openMemory: RecapMemoryLink?

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xl) {
            subtitle
            tiles
            activity
            if hasKinds { kinds }
            if !recap.highlights.isEmpty { highlights }
            streakLine
        }
    }

    private var subtitle: some View {
        HStack(spacing: LVSpacing.xs) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
            Text("\(RecapDates.rangeText(for: recap)) · Private to you")
        }
        .lvFont(.footnote)
        .foregroundStyle(palette.textSecondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Tiles

    private var tiles: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: LVSpacing.md), GridItem(.flexible(), spacing: LVSpacing.md)],
            spacing: LVSpacing.md
        ) {
            ForEach(RecapMetric.allCases) { metric in
                tile(metric)
            }
        }
    }

    private func tile(_ metric: RecapMetric) -> some View {
        let value = metric.value(in: recap.totals)
        let delta = metric.value(in: recap.totals) - metric.value(in: recap.previousTotals)
        let deltaText = RecapViewModel.deltaText(delta, comparedWith: vm.comparisonPhrase)
        return VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Label(metric.title, systemImage: metric.systemImage)
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
            Text("\(value)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .contentTransition(.numericText())
            Text(deltaText)
                .lvFont(.caption)
                .foregroundStyle(delta > 0 ? AnyShapeStyle(metric.color(in: palette)) : AnyShapeStyle(palette.textSecondary))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LVSpacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: LVRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.lg, style: .continuous)
                .strokeBorder(palette.surfaceStroke.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title): \(value), \(deltaText)")
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            sectionTitle("Daily activity")
            callout
            RecapActivityChart(
                days: RecapDates.chartDays(for: recap),
                range: recap.range,
                selection: Binding(get: { vm.selectedDate }, set: { vm.selectedDate = $0 }),
                selectedDay: vm.selectedDay,
                timeZone: RecapDates.timeZone(for: recap)
            )
            .frame(height: 180)
            RecapLegend(totals: recap.totals)
        }
    }

    /// The tapped day's breakdown, or the hint that days can be tapped.
    /// Above the chart rather than floating over it, so it never covers the
    /// bar it describes.
    @ViewBuilder private var callout: some View {
        if let day = vm.selectedDay {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(
                    Date.FormatStyle(timeZone: RecapDates.timeZone(for: recap)).weekday(.wide).month(.abbreviated).day()
                ))
                .lvFont(.fieldLabel)
                .foregroundStyle(palette.textPrimary)
                Text(RecapMetric.allCases.map { "\($0.value(in: day.day)) \($0.title.lowercased())" }.joined(separator: " · "))
                    .lvFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, LVSpacing.md)
            .padding(.vertical, LVSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            Text("Tap a day to see its breakdown")
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, LVSpacing.sm)
        }
    }

    // MARK: Kinds

    private var hasKinds: Bool {
        let k = recap.kinds
        return k.decision + k.preference + k.fact + k.note > 0
    }

    private var kinds: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            sectionTitle("What you learned")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LVSpacing.sm) { kindChips }
                VStack(alignment: .leading, spacing: LVSpacing.sm) { kindChips }
            }
        }
    }

    @ViewBuilder private var kindChips: some View {
        ForEach(MemoryKindDTO.allCases, id: \.self) { kind in
            let count = count(of: kind)
            HStack(spacing: LVSpacing.xs) {
                Text("\(count)")
                    .lvFont(.bodyEmphasis)
                    .monospacedDigit()
                Text(count == 1 ? kind.label.lowercased() : kind.pluralLabel.lowercased())
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, LVSpacing.md)
            .padding(.vertical, LVSpacing.sm)
            .background(palette.surface, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private func count(of kind: MemoryKindDTO) -> Int {
        switch kind {
        case .decision: recap.kinds.decision
        case .preference: recap.kinds.preference
        case .fact: recap.kinds.fact
        case .note: recap.kinds.note
        }
    }

    // MARK: Highlights

    private var highlights: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            sectionTitle("Highlights")
            VStack(spacing: 0) {
                ForEach(Array(recap.highlights.enumerated()), id: \.element.id) { index, highlight in
                    if index > 0 { Divider().padding(.leading, LVSpacing.xxl + LVSpacing.sm) }
                    highlightRow(highlight)
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: LVRadius.lg, style: .continuous))
        }
    }

    @ViewBuilder private func highlightRow(_ highlight: RecapHighlightDTO) -> some View {
        let label = HStack(spacing: LVSpacing.md) {
            Image(systemName: Self.symbol(for: highlight.kind))
                .foregroundStyle(palette.accent)
                .frame(width: LVSpacing.xxl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.title)
                    .lvFont(.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(Self.kindLabel(highlight.kind)) · \(highlight.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            if RecapViewModel.memoryID(for: highlight) != nil {
                Image(systemName: "chevron.right")
                    .lvFont(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.md)
        .contentShape(Rectangle())

        if let memoryID = RecapViewModel.memoryID(for: highlight) {
            Button {
                openMemory = RecapMemoryLink(id: memoryID)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the memory")
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    private static func symbol(for kind: RecapHighlightKind) -> String {
        switch kind {
        case .decision: "checkmark.seal"
        case .preference: "heart"
        case .achievement: "trophy"
        case .mostRevisited: "arrow.triangle.2.circlepath"
        case .unknown: "star"
        }
    }

    private static func kindLabel(_ kind: RecapHighlightKind) -> String {
        switch kind {
        case .decision: "Decision"
        case .preference: "Preference"
        case .achievement: "Achievement"
        case .mostRevisited: "Most revisited"
        case .unknown: "Highlight"
        }
    }

    // MARK: Streak

    private var streakLine: some View {
        HStack(spacing: LVSpacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Active \(recap.totals.activeDays) of \(recap.range.days) days · \(recap.totals.streakDays)-day streak")
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .lvFont(.headline)
            .foregroundStyle(palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Plumbing

/// `.navigationDestination(item:)` fodder for a highlight's memory.
struct RecapMemoryLink: Identifiable, Hashable {
    let id: UUID
}

/// What the share sheet sends: the rendered card and the server's
/// numbers-only text.
private struct RecapSharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

/// Shape-only data for the redacted loading state.
enum RecapPlaceholder {
    static let recap = MeRecapResponse(
        range: .week,
        start: "2026-01-01",
        end: "2026-01-07",
        timezone: TimeZone.current.identifier,
        totals: RecapTotalsDTO(captures: 12, learned: 4, asked: 6, reviewed: 3, activeDays: 5, streakDays: 3),
        previousTotals: RecapTotalsDTO(captures: 9, learned: 4, asked: 2, reviewed: 1),
        daily: (1...7).map { RecapDayDTO(date: "2026-01-0\($0)", captures: $0 % 3 + 1, learned: $0 % 2, asked: 1) },
        kinds: RecapKindsDTO(),
        highlights: [],
        shareText: ""
    )
}
