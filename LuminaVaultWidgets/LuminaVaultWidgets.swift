//
//  LuminaVaultWidgets.swift
//  LuminaVaultWidgets
//
//  Recent captures on the home screen.
//
//  Reads `WidgetSnapshotStore` from the shared App Group container and never
//  touches the network. A widget extension is a separate process with its own
//  sandbox: it cannot read the host app's keychain, so it holds no bearer token
//  and cannot make an authenticated API call. It also runs on a very short
//  budget. The app publishes a snapshot on capture; this just renders it.
//

import SwiftUI
import WidgetKit

struct RecentCapturesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct RecentCapturesProvider: TimelineProvider {
    func placeholder(in _: Context) -> RecentCapturesEntry {
        RecentCapturesEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentCapturesEntry) -> Void) {
        // The gallery preview must never show a real user's notes.
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : WidgetSnapshotStore.read()
        completion(RecentCapturesEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RecentCapturesEntry>) -> Void) {
        let entry = RecentCapturesEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
        // The app calls WidgetCenter.reloadTimelines on every capture, so this
        // interval is only a backstop against relative timestamps going stale.
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery and while the real snapshot loads.
    static let placeholder = WidgetSnapshot(
        items: [
            WidgetCaptureItem(id: UUID(), title: "Ideas for the launch video", createdAt: Date()),
            WidgetCaptureItem(
                id: UUID(),
                title: "Coffee with Sam — follow up on the API docs",
                createdAt: Date().addingTimeInterval(-3600),
                placeName: "Blue Bottle"
            ),
            WidgetCaptureItem(
                id: UUID(),
                title: "Read: distributed systems paper",
                createdAt: Date().addingTimeInterval(-7200)
            ),
        ],
        totalCount: 128,
        updatedAt: Date()
    )
}

struct LuminaVaultWidgetsEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: RecentCapturesProvider.Entry

    private var visibleItems: [WidgetCaptureItem] {
        Array(entry.snapshot.items.prefix(family == .systemLarge ? 5 : 3))
    }

    var body: some View {
        if entry.snapshot.items.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                ForEach(visibleItems) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "brain.head.profile")
                .font(.caption2)
                .accessibilityHidden(true)
            Text("Recent")
                .font(.caption2.weight(.semibold))
            Spacer()
            if entry.snapshot.totalCount > 0 {
                Text("\(entry.snapshot.totalCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func row(_ item: WidgetCaptureItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(family == .systemSmall ? 1 : 2)
            HStack(spacing: 4) {
                Text(item.createdAt, style: .relative)
                if let placeName = item.placeName, !placeName.isEmpty, family != .systemSmall {
                    Text("·")
                    Text(placeName).lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One label per row so VoiceOver reads a coherent sentence rather than
        // three disconnected fragments.
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing captured yet")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
            Text("Your recent notes will appear here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LuminaVaultWidgets: Widget {
    let kind: String = "LuminaVaultWidgets"

    var body: some WidgetConfiguration {
        // StaticConfiguration, not AppIntentConfiguration: there is nothing for
        // the user to configure, and a configuration intent would add a second
        // AppIntent surface alongside the app's Capture/Ask shortcuts.
        StaticConfiguration(kind: kind, provider: RecentCapturesProvider()) { entry in
            LuminaVaultWidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Captures")
        .description("Your latest notes from LuminaVault.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    LuminaVaultWidgets()
} timeline: {
    RecentCapturesEntry(date: .now, snapshot: .placeholder)
    RecentCapturesEntry(date: .now, snapshot: .empty)
}
