//
//  ResurfaceWidget.swift
//  LuminaVaultWidgets
//
//  "Today's memory": the head of Home's resurface queue on the home screen.
//
//  Reads `ResurfaceWidgetStore` from the App Group; the app writes it whenever
//  the queue loads or changes. Tapping opens the memory
//  (`luminavault://memory/<id>`). The medium size also answers it in place —
//  Soon, Later, Never — through `ResurfaceActionIntent`.
//

import AppIntents
import SwiftUI
import WidgetKit

struct ResurfaceEntry: TimelineEntry {
    let date: Date
    let item: ResurfaceWidgetItem?
    /// Memories left including this one.
    let remaining: Int
}

struct ResurfaceProvider: TimelineProvider {
    func placeholder(in _: Context) -> ResurfaceEntry {
        ResurfaceEntry(date: Date(), item: .placeholder, remaining: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (ResurfaceEntry) -> Void) {
        // The gallery preview must never show a real user's memory.
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ResurfaceEntry>) -> Void) {
        // The app reloads this kind whenever the queue changes; the interval
        // is only a backstop.
        let refresh = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        completion(Timeline(entries: [currentEntry()], policy: .after(refresh)))
    }

    private func currentEntry() -> ResurfaceEntry {
        let snapshot = ResurfaceWidgetStore.shared.read()
        return ResurfaceEntry(date: Date(), item: snapshot.current, remaining: snapshot.items.count)
    }
}

extension ResurfaceWidgetItem {
    static let placeholder = ResurfaceWidgetItem(
        memoryId: UUID(),
        snippet: "Decided to keep the API flat — no nested resources until a second client needs them.",
        why: "Saved a year ago today"
    )
}

struct ResurfaceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ResurfaceEntry

    var body: some View {
        if let item = entry.item {
            content(item)
                .widgetURL(item.deepLink)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(_ item: ResurfaceWidgetItem) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("To revisit", systemImage: "arrow.counterclockwise")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(item.snippet)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 6) {
                header
                text(item, snippetLines: 2)
                Spacer(minLength: 0)
                answers(item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                header
                text(item, snippetLines: 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.counterclockwise")
                .accessibilityHidden(true)
            Text("To revisit")
                .textCase(.uppercase)
                .kerning(0.8)
            Spacer(minLength: 0)
            if entry.remaining > 1, family != .systemSmall {
                Text("1 of \(entry.remaining)")
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func text(_ item: ResurfaceWidgetItem, snippetLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.snippet)
                .font(.subheadline.weight(.medium))
                .lineLimit(snippetLines)
            Text(item.why)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func answers(_ item: ResurfaceWidgetItem) -> some View {
        HStack(spacing: 6) {
            Button("Soon", intent: ResurfaceActionIntent(memoryID: item.memoryId, action: .soon))
                .accessibilityLabel("Show it again in a few days")
            Button("Later", intent: ResurfaceActionIntent(memoryID: item.memoryId, action: .later))
                .accessibilityLabel("Show it again in about a month")
            Spacer(minLength: 0)
            Button(intent: ResurfaceActionIntent(memoryID: item.memoryId, action: .never)) {
                Image(systemName: "eye.slash")
            }
            .accessibilityLabel("Never show this again")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(family == .accessoryRectangular ? .caption : .title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing to revisit today")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResurfaceWidget: Widget {
    let kind: String = ResurfaceWidgetStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ResurfaceProvider()) { entry in
            ResurfaceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's memory")
        .description("Something from your vault worth seeing again.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemMedium) {
    ResurfaceWidget()
} timeline: {
    ResurfaceEntry(date: .now, item: .placeholder, remaining: 3)
    ResurfaceEntry(date: .now, item: nil, remaining: 0)
}
