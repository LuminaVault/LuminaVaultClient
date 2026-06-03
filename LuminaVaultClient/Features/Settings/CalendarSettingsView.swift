// LuminaVaultClient/LuminaVaultClient/Features/Settings/CalendarSettingsView.swift
//
// HER-340 — Settings → Connections → Google Calendar. Connect/disconnect via
// the OAuth handoff, see upcoming synced events, and add an event ("Add to
// Calendar"). Hermes gains schedule awareness server-side once connected.

import AuthenticationServices
import LuminaVaultShared
import SwiftUI
import UIKit

struct CalendarSettingsView: View {
    @State private var viewModel = CalendarSettingsViewModel()
    @State private var showDisconnectConfirm = false
    @State private var showAddSheet = false

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .ready(status):
                statusSection(status)
                if status.connected {
                    eventsSection
                }
            case let .failed(message):
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
            }

            if let err = viewModel.lastError {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Google Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog(
            "Disconnect Google Calendar?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Disconnect", role: .destructive) { Task { await viewModel.disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Revokes access and removes synced events from your brain. You can reconnect any time.")
        }
        .sheet(isPresented: $showAddSheet) {
            AddCalendarEventSheet { title, start, end, location, notes in
                await viewModel.addEvent(title: title, startsAt: start, endsAt: end, location: location, notes: notes)
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ status: CalendarStatusResponse) -> some View {
        Section("Google Calendar") {
            LabeledContent("Status", value: status.connected ? "Connected" : "Not connected")
                .foregroundStyle(status.connected ? .green : .secondary)
            if let email = status.accountEmail {
                LabeledContent("Account", value: email)
            }
            if status.needsReauth {
                Text("Access expired — reconnect to resume syncing.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let synced = status.lastSyncedAt {
                LabeledContent("Last synced") {
                    Text(synced, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            if status.connected {
                Button("Add to Calendar", systemImage: "plus") { showAddSheet = true }
                    .disabled(viewModel.isWorking)
                Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                    .disabled(viewModel.isWorking)
            } else {
                Button("Connect Google Calendar") {
                    Task { await viewModel.connect(anchor: Self.presentationAnchor()) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }
        } footer: {
            Text("Lets Hermes see your schedule when you chat, find free time, and add events. Read + write access to your Google Calendar events.")
        }
    }

    private var eventsSection: some View {
        Section("Upcoming") {
            if viewModel.events.isEmpty {
                Text("No upcoming events synced yet.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.body)
                        Text(Self.range(event)).font(.caption).foregroundStyle(.secondary)
                        if let location = event.location, !location.isEmpty {
                            Text(location).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private static func range(_ event: CalendarEventDTO) -> String {
        if event.allDay {
            return event.startsAt.formatted(.dateTime.weekday().month().day()) + " · all day"
        }
        let start = event.startsAt.formatted(.dateTime.weekday().month().day().hour().minute())
        let end = event.endsAt.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private static func presentationAnchor() -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

/// Minimal "Add to Calendar" form. Defaults to a 1-hour block starting at the
/// next round hour.
private struct AddCalendarEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Date, Date, String?, String?) async -> Bool

    @State private var title = ""
    @State private var startsAt = AddCalendarEventSheet.defaultStart()
    @State private var endsAt = AddCalendarEventSheet.defaultStart().addingTimeInterval(3600)
    @State private var location = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $startsAt)
                    DatePicker("Ends", selection: $endsAt, in: startsAt...)
                }
                Section {
                    TextField("Location (optional)", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isSaving = true
                            let ok = await onSave(
                                title.trimmingCharacters(in: .whitespacesAndNewlines),
                                startsAt, endsAt,
                                location, notes,
                            )
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || endsAt <= startsAt)
                }
            }
        }
    }

    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let next = cal.date(bySetting: .minute, value: 0, of: Date().addingTimeInterval(3600)) ?? Date()
        return next
    }
}
