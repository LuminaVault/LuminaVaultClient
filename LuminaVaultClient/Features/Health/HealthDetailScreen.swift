// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthDetailScreen.swift
import Charts
import SwiftUI

/// HER-118 — full-screen detail navigated to on dashboard card tap.
/// Header chart shows the daily aggregation window (range selectable
/// 7 / 30 / 90 days); section below lists the most recent raw samples
/// from `GET /v1/health?type=&limit=50`.
struct HealthDetailScreen: View {
    let metric: HealthMetric
    @Bindable var viewModel: HealthDashboardViewModel
    @State private var rangeDays: Int = 7
    @State private var samples: [HealthEventDTO] = []
    @State private var samplesLoadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                chartHeader
                rangeSelector
                samplesSection
            }
            .padding()
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rangeDays) {
            await viewModel.refresh(days: rangeDays)
        }
        .task {
            await loadSamples()
        }
    }

    private var chartHeader: some View {
        let aggregate = viewModel.aggregates[metric.serverType]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(.tint)
                Text("Latest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedLatest)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let aggregate, !aggregate.days.isEmpty {
                Chart(aggregate.days, id: \.date) { day in
                    LineMark(
                        x: .value("Day", day.date),
                        y: .value(metric.title, day.value),
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.tint)
                    AreaMark(
                        x: .value("Day", day.date),
                        y: .value(metric.title, day.value),
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.tint.opacity(0.15))
                }
                .frame(height: 200)
            } else {
                ProgressView()
                    .frame(height: 200)
            }
        }
    }

    private var rangeSelector: some View {
        Picker("Range", selection: $rangeDays) {
            Text("7d").tag(7)
            Text("30d").tag(30)
            Text("90d").tag(90)
        }
        .pickerStyle(.segmented)
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent samples")
                .font(.headline)
            switch samplesLoadState {
            case .idle, .loading:
                ProgressView()
            case let .failed(message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loaded:
                if samples.isEmpty {
                    Text("No samples in this window.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(samples, id: \.id) { sample in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sample.recordedAt, style: .date)
                                        .font(.caption)
                                    Text(sample.recordedAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sampleValue(sample))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var formattedLatest: String {
        let value = viewModel.latestValue(for: metric)
        if value == 0 { return "–" }
        switch metric {
        case .sleep:
            return String(format: "%.1f hr", value / 60.0)
        case .steps:
            return Int(value.rounded()).formatted(.number)
        case .heartRate, .hrv:
            return Int(value.rounded()).formatted(.number)
        }
    }

    private func sampleValue(_ sample: HealthEventDTO) -> String {
        if let n = sample.valueNumeric {
            return "\(Int(n.rounded())) \(sample.unit ?? metric.unit)"
        }
        return sample.valueText ?? "—"
    }

    private func loadSamples() async {
        samplesLoadState = .loading
        do {
            let resp = try await viewModel.endpointsExecutor.listSamples(type: metric.serverType, limit: 50)
            samples = resp.events
            samplesLoadState = .loaded
        } catch {
            samplesLoadState = .failed(error.localizedDescription)
        }
    }
}
