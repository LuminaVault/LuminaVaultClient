// LuminaVaultClient/LuminaVaultClient/Features/Recap/RecapViewModel.swift
//
// The recap sheet's state: one `MeRecapResponse` per range, the day the
// chart has selected, and the arithmetic the tiles show (deltas against the
// window before). The server does the counting; this only compares.

import Foundation
import LuminaVaultShared
import Observation

/// One of the four things the recap counts. UI-only.
enum RecapMetric: String, CaseIterable, Identifiable, Sendable {
    case captures
    case learned
    case asked
    case reviewed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captures: "Captures"
        case .learned: "Learned"
        case .asked: "Asked"
        case .reviewed: "Reviewed"
        }
    }

    var systemImage: String {
        switch self {
        case .captures: "tray.and.arrow.down"
        case .learned: "sparkles"
        case .asked: "bubble.left.and.text.bubble.right"
        case .reviewed: "arrow.counterclockwise"
        }
    }

    func value(in totals: RecapTotalsDTO) -> Int {
        switch self {
        case .captures: totals.captures
        case .learned: totals.learned
        case .asked: totals.asked
        case .reviewed: totals.reviewed
        }
    }

    func value(in day: RecapDayDTO) -> Int {
        switch self {
        case .captures: day.captures
        case .learned: day.learned
        case .asked: day.asked
        case .reviewed: day.reviewed
        }
    }
}

/// A recap day with its calendar date resolved, for the chart. UI-only.
struct RecapChartDay: Identifiable, Equatable, Sendable {
    let day: RecapDayDTO
    let date: Date

    var id: String { day.date }
    var total: Int { RecapMetric.allCases.reduce(0) { $0 + $1.value(in: day) } }
}

/// Parsing and formatting for the recap's `yyyy-MM-dd` local days. The
/// server names the timezone it counted in, and the dates are read in it so
/// "Oct 15" is the day the user lived, not the day UTC did.
enum RecapDates {
    static func timeZone(for recap: MeRecapResponse) -> TimeZone {
        TimeZone(identifier: recap.timezone) ?? .current
    }

    static func date(from day: String, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "Oct 9 – Oct 15", in the user's locale.
    static func rangeText(for recap: MeRecapResponse, locale: Locale = .autoupdatingCurrent) -> String {
        let zone = timeZone(for: recap)
        guard let start = date(from: recap.start, in: zone),
              let end = date(from: recap.end, in: zone)
        else { return "\(recap.start) – \(recap.end)" }
        let style = Date.FormatStyle(locale: locale, timeZone: zone)
            .month(.abbreviated)
            .day()
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    static func chartDays(for recap: MeRecapResponse) -> [RecapChartDay] {
        let zone = timeZone(for: recap)
        return recap.daily.compactMap { day in
            date(from: day.date, in: zone).map { RecapChartDay(day: day, date: $0) }
        }
    }
}

@MainActor
@Observable
final class RecapViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded(MeRecapResponse)
        case failed(String)
    }

    /// The ranges the sheet offers. The server accepts exactly these two.
    static let ranges: [AnalyticsRange] = [.week, .month]

    private(set) var range: AnalyticsRange
    private(set) var state: LoadState = .loading
    /// The chart's tapped day, or nil for the "Tap a day" hint.
    var selectedDate: Date?

    private var cache: [AnalyticsRange: MeRecapResponse] = [:]
    private let client: any RecapClientProtocol

    /// `initial` is what Home's strip already loaded for the week, so the
    /// sheet opens on numbers instead of a spinner.
    init(
        client: any RecapClientProtocol,
        range: AnalyticsRange = .week,
        initial: MeRecapResponse? = nil
    ) {
        self.client = client
        self.range = range
        if let initial {
            cache[initial.range] = initial
            if initial.range == range { state = .loaded(initial) }
        }
    }

    var recap: MeRecapResponse? {
        if case let .loaded(recap) = state { return recap }
        return nil
    }

    var title: String {
        switch range {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 90 days"
        }
    }

    /// What a delta is measured against, in words.
    var comparisonPhrase: String {
        switch range {
        case .week: "last week"
        case .month: "the previous 30 days"
        case .quarter: "the previous 90 days"
        }
    }

    /// Loads the current range unless it is already in hand.
    func load() async {
        if let cached = cache[range] {
            state = .loaded(cached)
            return
        }
        await fetch()
    }

    /// Always asks the server; for pull-to-refresh and "Try again".
    func reload() async {
        cache[range] = nil
        await fetch()
    }

    func select(range newRange: AnalyticsRange) async {
        guard newRange != range else { return }
        range = newRange
        selectedDate = nil
        await load()
    }

    private func fetch() async {
        let requested = range
        if recap?.range != requested { state = .loading }
        do {
            let response = try await client.recap(range: requested)
            cache[requested] = response
            // The picker may have moved on while this was in flight.
            guard requested == range else { return }
            state = .loaded(response)
        } catch {
            guard requested == range else { return }
            state = .failed("Couldn't load your recap.")
        }
    }

    // MARK: - Arithmetic

    func delta(for metric: RecapMetric) -> Int? {
        guard let recap else { return nil }
        return metric.value(in: recap.totals) - metric.value(in: recap.previousTotals)
    }

    /// "+3 vs last week", "−2 vs last week", "same as last week".
    func deltaText(for metric: RecapMetric) -> String? {
        guard let delta = delta(for: metric) else { return nil }
        return Self.deltaText(delta, comparedWith: comparisonPhrase)
    }

    nonisolated static func deltaText(_ delta: Int, comparedWith phrase: String) -> String {
        if delta == 0 { return "same as \(phrase)" }
        let sign = delta > 0 ? "+" : "\u{2212}"
        return "\(sign)\(abs(delta)) vs \(phrase)"
    }

    var chartDays: [RecapChartDay] {
        recap.map(RecapDates.chartDays(for:)) ?? []
    }

    /// The day the chart's selection falls on. Matched by calendar day in the
    /// recap's timezone, since a drag lands anywhere inside the bar.
    var selectedDay: RecapChartDay? {
        guard let selectedDate, let recap else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = RecapDates.timeZone(for: recap)
        return chartDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var rangeText: String? {
        recap.map { RecapDates.rangeText(for: $0) }
    }

    /// Memory highlights open the memory; achievements are just news.
    static func memoryID(for highlight: RecapHighlightDTO) -> UUID? {
        switch highlight.kind {
        case .decision, .preference, .mostRevisited:
            UUID(uuidString: highlight.refId)
        case .achievement, .unknown:
            nil
        }
    }
}
