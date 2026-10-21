// LuminaVaultClient/LuminaVaultClient/Features/MeetingBrief/MeetingBriefSheet.swift
//
// The pre-meeting brief, as a sheet: the meeting (title, time, place,
// people), the one line on why, and the notes that bear on it. Opened from
// `luminavault://meeting/<eventId>` — a tap on the quiet push that goes out
// about half an hour before, or its "Open" action — over whatever is up.
//
// A note opens in `MemoryDetailSheet`. With nothing saved about the meeting
// the sheet says so; for an event that is no longer in the calendar, it
// says that instead of a generic error.

import LuminaVaultShared
import SwiftUI

struct MeetingBriefSheet: View {
    @State private var vm: MeetingBriefViewModel
    /// The note a row opened.
    @State private var openMemory: MeetingBriefMemoryLink?
    /// Bumped by "Try again". Zero is the first load.
    @State private var reloadToken = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private let memoryClient: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        viewModel: MeetingBriefViewModel,
        memoryClient: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.memoryClient = memoryClient
        self.spacesClient = spacesClient
    }

    var body: some View {
        NavigationStack {
            content
                .background(palette.backgroundBase)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task(id: reloadToken) { await vm.load() }
                .sheet(item: $openMemory) { link in
                    MemoryDetailSheet(memoryID: link.id, client: memoryClient, spacesClient: spacesClient)
                }
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading your meeting brief")
        case .notFound:
            ContentUnavailableView(
                "This meeting isn't in your calendar",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("It may have been moved, cancelled or deleted since the reminder went out.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label(message, systemImage: "calendar")
            } actions: {
                Button("Try again") { reloadToken += 1 }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: LVSpacing.xs, bottom: LVSpacing.xs, trailing: LVSpacing.xs))
                    .listRowBackground(Color.clear)
            }

            if let why = vm.whyText {
                Section {
                    Label {
                        Text(why)
                            .lvFont(.callout)
                            .foregroundStyle(palette.textPrimary)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(palette.accent)
                    }
                }
            }

            if vm.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(vm.memories) { memory in
                        Button {
                            openMemory = MeetingBriefMemoryLink(id: memory.id)
                        } label: {
                            MeetingBriefMemoryRow(snippet: memory.snippet, meta: vm.metaText(for: memory))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("From your notes")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(vm.brief?.event.title ?? "")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                // Room for a round capital's overshoot at the row's edge.
                .padding(.leading, 1)
            if let time = vm.timeRangeText {
                detail(time, systemImage: "clock")
            }
            if let location = vm.locationText {
                detail(location, systemImage: "mappin.and.ellipse")
            }
            if let attendees = vm.attendeesText {
                detail(attendees, systemImage: "person.2")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Icon and text in a tight row: a `Label` in a list takes the list's
    /// wide icon column, which leaves the text floating mid-row.
    private func detail(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LVSpacing.md) {
            Image(systemName: "note.text")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Nothing saved about this meeting yet")
                .lvFont(.headline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("Notes that mention it or the people in it will show up here.")
                .lvFont(.callout)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}

/// One note: its first line or so, and what kind it is and when it was saved.
private struct MeetingBriefMemoryRow: View {
    let snippet: String
    let meta: String

    @Environment(\.lvPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(snippet)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LVSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note")
    }
}

private struct MeetingBriefMemoryLink: Identifiable, Equatable {
    let id: UUID
}
