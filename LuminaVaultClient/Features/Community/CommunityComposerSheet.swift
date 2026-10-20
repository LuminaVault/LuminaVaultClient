// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityComposerSheet.swift
//
// New thread: a title (3–120) and a body (1–4,000). A post the automatic
// check holds comes back `pending` and shows "Awaiting review" to its author;
// one it rejects never posts, and says so in plain words.

import LuminaVaultShared
import SwiftUI

struct CommunityComposerSheet: View {
    let onSubmit: (_ title: String, _ body: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    static let titleRange = 3...120
    static let bodyLimit = 4000

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBody: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        !isSending
            && Self.titleRange.contains(trimmedTitle.count)
            && (1...Self.bodyLimit).contains(trimmedBody.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .lineLimit(6...16)
                } footer: {
                    Text("Be kind. Posts follow the Community Guidelines and may be reviewed before others see them.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
            .onAppear { titleFocused = true }
            .interactiveDismissDisabled(isSending)
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await onSubmit(trimmedTitle, trimmedBody)
            dismiss()
        } catch {
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }
}
