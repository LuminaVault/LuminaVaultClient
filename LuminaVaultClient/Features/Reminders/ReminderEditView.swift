// LuminaVaultClient/LuminaVaultClient/Features/Reminders/ReminderEditView.swift
//
// HER-55 — create / edit sheet for a server-backed reminder. Presented from
// RemindersListView (toolbar "+" to create, row tap to edit). On save it hands
// a ReminderCreateRequest / ReminderPatchRequest back to the caller, which owns
// the HTTP call + list refresh.

import LuminaVaultShared
import SwiftUI

struct ReminderEditView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new reminder; non-nil = editing an existing one.
    let existing: ReminderDTO?
    /// Persist callback. Throwing so the sheet can surface a save failure.
    let onSave: (ReminderDraft) async throws -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var fireAt: Date
    @State private var isRecurring: Bool
    @State private var recurrenceCron: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existing: ReminderDTO?, onSave: @escaping (ReminderDraft) async throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _bodyText = State(initialValue: existing?.body ?? "")
        _fireAt = State(initialValue: existing?.fireAt ?? Date().addingTimeInterval(3600))
        _isRecurring = State(initialValue: existing?.recurrenceCron != nil)
        _recurrenceCron = State(initialValue: existing?.recurrenceCron ?? "0 9 * * *")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    TextField("Title", text: $title)
                    TextField("Details (optional)", text: $bodyText, axis: .vertical)
                        .lineLimit(1 ... 4)
                }
                Section("When") {
                    DatePicker("Fire at", selection: $fireAt)
                    Toggle("Repeat", isOn: $isRecurring)
                    if isRecurring {
                        TextField("Cron (e.g. 0 9 * * 1-5)", text: $recurrenceCron)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let draft = ReminderDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            fireAt: fireAt,
            recurrenceCron: isRecurring ? recurrenceCron.trimmingCharacters(in: .whitespaces) : nil,
        )
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorMessage = "Couldn't save reminder. Check the cron and try again."
            isSaving = false
        }
    }
}

/// Plain value the sheet emits; the caller maps it to a create or patch request.
struct ReminderDraft: Sendable {
    let title: String
    let body: String
    let fireAt: Date
    let recurrenceCron: String?
}
