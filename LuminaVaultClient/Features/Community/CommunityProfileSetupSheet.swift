// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityProfileSetupSheet.swift
//
// The board shows people by a community handle and display name — never the
// account's username or email. Posting needs one, plus agreement to the
// current Community Guidelines version.

import LuminaVaultShared
import SwiftUI

struct CommunityProfileSetupSheet: View {
    /// Prefills when editing an existing profile.
    let existing: CommunityProfileDTO?
    let onSave: (_ handle: String, _ displayName: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var handle: String
    @State private var displayName: String
    @State private var agreed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existing: CommunityProfileDTO?, onSave: @escaping (_ handle: String, _ displayName: String) async throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _handle = State(initialValue: existing?.handle ?? "")
        _displayName = State(initialValue: existing?.displayName ?? "")
    }

    /// Mirrors the server's `^[a-z0-9_]{3,20}$`.
    static func isValidHandle(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9_]{3,20}$"#, options: .regularExpression) != nil
    }

    private var normalizedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && agreed && Self.isValidHandle(normalizedHandle) && (1...40).contains(trimmedName.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Display name", text: $displayName)
                        .textContentType(.nickname)
                } header: {
                    Text("Your community profile")
                } footer: {
                    Text("Handles are 3–20 lowercase letters, numbers or underscores. "
                        + "Other members see only your handle and display name.")
                }

                Section {
                    Toggle("I agree to the Community Guidelines", isOn: $agreed)
                    Link("Read the Community Guidelines", destination: Config.termsOfServiceURL)
                } footer: {
                    Text("No harassment, hate, sexual content or spam. Posts may be reviewed, and you can report or block anyone.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Join the community" : "Community profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(normalizedHandle, trimmedName)
            dismiss()
        } catch {
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }
}
