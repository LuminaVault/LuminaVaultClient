// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityReportSheet.swift
//
// Report a post: a reason, an optional note (≤ 500 characters), send. The
// server answers 202; a moderator takes it from there.

import LuminaVaultShared
import SwiftUI

struct CommunityReportSheet: View {
    let post: CommunityPostDTO
    let onSubmit: (CommunityReportReason, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: CommunityReportReason = .spam
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    static let noteLimit = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(CommunityReportReason.allCases, id: \.self) { reason in
                            Text(CommunityPresentation.reasonLabel(reason)).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Why are you reporting this post?")
                }

                Section {
                    TextField("Add details (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: note) { _, value in
                            if value.count > Self.noteLimit { note = String(value.prefix(Self.noteLimit)) }
                        }
                } footer: {
                    Text("Reports are anonymous. The author isn't told who reported them.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .disabled(isSending)
                }
            }
            .alert("Thanks for reporting", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("A moderator will review this post.")
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await onSubmit(reason, note)
            sent = true
        } catch {
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }
}
