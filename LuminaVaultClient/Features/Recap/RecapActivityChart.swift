// LuminaVaultClient/LuminaVaultClient/Features/Recap/RecapActivityChart.swift
//
// Daily activity as stacked bars, one colour per thing counted. Shared by the
// recap sheet (selectable) and the share card (static, rendered to an image).

import Charts
import LuminaVaultShared
import SwiftUI

extension RecapMetric {
    /// One hue per series, distinct in both schemes. Captures and learned
    /// take the palette's identity colours; the other two take system hues
    /// far from both, so a stack never reads as one colour.
    func color(in palette: LVPalette) -> Color {
        switch self {
        case .captures: palette.primary
        case .learned: palette.accent
        case .asked: Color(uiColor: .systemPurple)
        case .reviewed: Color(uiColor: .systemPink)
        }
    }
}

struct RecapActivityChart: View {
    let days: [RecapChartDay]
    let range: AnalyticsRange
    /// Nil makes the chart static (the share card).
    var selection: Binding<Date?>?
    /// The selected day, highlighted with a rule behind the stack.
    var selectedDay: RecapChartDay?
    var timeZone: TimeZone = .current

    @Environment(\.lvPalette) private var palette

    var body: some View {
        chart
            .chartForegroundStyleScale(
                domain: RecapMetric.allCases.map(\.title),
                range: RecapMetric.allCases.map { $0.color(in: palette) }
            )
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { _ in
                    AxisValueLabel(format: xAxisFormat, centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .environment(\.timeZone, timeZone)
    }

    @ViewBuilder private var chart: some View {
        let base = Chart {
            if let selectedDay {
                RuleMark(x: .value("Day", selectedDay.date, unit: .day))
                    .foregroundStyle(Color(uiColor: .systemFill))
                    .lineStyle(StrokeStyle(lineWidth: barWidthHint))
                    .accessibilityHidden(true)
            }
            ForEach(days) { day in
                ForEach(RecapMetric.allCases) { metric in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Count", metric.value(in: day.day))
                    )
                    .foregroundStyle(by: .value("Series", metric.title))
                    .accessibilityLabel(day.date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide).month().day()))
                    .accessibilityValue("\(metric.value(in: day.day)) \(metric.title.lowercased())")
                }
            }
        }
        if let selection {
            base.chartXSelection(value: selection)
        } else {
            base
        }
    }

    /// Wide enough to sit behind a bar like a highlight, not a hairline.
    private var barWidthHint: CGFloat {
        range == .week ? 28 : 8
    }

    private var xAxisValues: AxisMarkValues {
        range == .week ? .stride(by: .day) : .stride(by: .day, count: 7)
    }

    private var xAxisFormat: Date.FormatStyle {
        let style = Date.FormatStyle(timeZone: timeZone)
        return range == .week ? style.weekday(.narrow) : style.month(.abbreviated).day()
    }
}

/// Coloured dots with each series' total, under the chart.
struct RecapLegend: View {
    let totals: RecapTotalsDTO

    @Environment(\.lvPalette) private var palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LVSpacing.md) { items }
            VStack(alignment: .leading, spacing: LVSpacing.xs) { items }
        }
    }

    @ViewBuilder private var items: some View {
        ForEach(RecapMetric.allCases) { metric in
            HStack(spacing: LVSpacing.xs) {
                Circle()
                    .fill(metric.color(in: palette))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("\(metric.title) \(metric.value(in: totals))")
                    .lvFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
