// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeGlanceStrip.swift
//
// Three numbers, one row.
//
// This is what survived of the Dashboard: what you saved today, how many days
// you have kept it up, and how much is waiting to be re-read. Each tile shows
// a placeholder while its call is in flight and a dash if that call failed,
// because a tile that quietly reads zero is a lie about the vault.

import SwiftUI

struct HomeGlanceStrip: View {
    typealias Count = HomeGlanceViewModel.CardState<Int>

    let memoriesToday: Count
    let streakDays: Count
    let toRevisit: Count

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            tile("Today", memoriesToday) { "\($0)" }
            tile("Streak", streakDays) { "\($0)d" }
            tile("To revisit", toRevisit) { "\($0)" }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tile(_ label: String, _ state: Count, _ format: (Int) -> String) -> some View {
        VStack(spacing: 4) {
            Text(value(of: state, format))
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .redacted(reason: isLoading(state) ? .placeholder : [])
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(accessibleValue(of: state, format))")
    }

    private func value(of state: Count, _ format: (Int) -> String) -> String {
        switch state {
        case .loading: return format(0)
        case .loaded(let count): return format(count)
        case .failed: return "—"
        }
    }

    private func accessibleValue(of state: Count, _ format: (Int) -> String) -> String {
        switch state {
        case .loading: return "loading"
        case .loaded(let count): return format(count)
        case .failed: return "unavailable"
        }
    }

    private func isLoading(_ state: Count) -> Bool {
        if case .loading = state { return true }
        return false
    }
}

#Preview {
    List {
        Section("Today") {
            HomeGlanceStrip(memoriesToday: .loaded(7), streakDays: .loaded(3), toRevisit: .failed(message: "nope"))
            HomeGlanceStrip(memoriesToday: .loading, streakDays: .loading, toRevisit: .loading)
        }
    }
}
