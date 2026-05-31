// LuminaVaultClient/LuminaVaultClient/Features/Vault/MarkdownReaderView.swift
// HER-105: in-app reader for a single vault file. Markdown gets rendered
// via SwiftUI text with Obsidian-compatible wikilink routing. Binary files
// fall through to a placeholder.
// HER-Notes: text/markdown files are now editable like Apple Notes — edit
// the body, set a title + tags, promote to a smart todo (done + due date
// with a local reminder), and delete. Saving re-PUTs the note so the server
// re-embeds its recall memory in place (no separate memory call).
import LuminaVaultShared
import SwiftUI

struct MarkdownReaderView: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let file: VaultFileDTO
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    /// Optional — when absent the note is read-only (e.g. the Reflect
    /// surface, which renders saved syntheses without an edit affordance).
    var uploadClient: (any VaultUploadClientProtocol)? = nil

    @State private var rawText: String?
    @State private var isMarkdown = false
    @State private var isLoading = true
    @State private var error: String?

    // Edit state
    @State private var isEditing = false
    @State private var draftBody: String = ""
    @State private var draftTitle: String = ""
    @State private var draftTagsText: String = ""
    @State private var draftIsTodo = false
    @State private var draftDone = false
    @State private var draftHasDue = false
    @State private var draftDueAt: Date = .now.addingTimeInterval(3600)
    @State private var saving = false
    @State private var showDeleteConfirm = false

    /// Only text/markdown notes are editable, and only when an upload client
    /// is available to persist the edit.
    private var isEditable: Bool {
        uploadClient != nil && (file.contentType.contains("markdown") || file.path.hasSuffix(".md"))
    }

    private var displayTitle: String {
        let t = file.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t, !t.isEmpty { return t }
        return (file.path as NSString).lastPathComponent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isEditing {
                    editor
                } else {
                    reader
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .lvBackground()
        .navigationTitle(isEditing ? "Edit" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteNote() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await load() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditable {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(saving)
                } else {
                    Menu {
                        Button { beginEditing() } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isEditing = false }
                }
            }
        }
    }

    // MARK: - Reader

    @ViewBuilder
    private var reader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if file.metadata?.isTodo == true {
                Image(systemName: (file.metadata?.done == true) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(palette.glowPrimary)
                    .font(.system(size: 20))
            }
            Text(displayTitle)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .strikethrough(file.metadata?.done == true, color: palette.textSecondary)
        }

        metaBadges

        Divider().background(palette.surfaceStroke)

        if isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else if let error {
            Text(error).font(.system(size: 13)).foregroundStyle(.red.opacity(0.85))
        } else if let rawText, isMarkdown {
            WikilinkMarkdownView(markdown: rawText, vaultClient: vaultClient, memoryClient: memoryClient)
        } else if let rawText {
            Text(rawText)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            Text("Binary file — preview unavailable.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var metaBadges: some View {
        let tags = file.metadata?.tags ?? []
        if !tags.isEmpty || file.metadata?.dueAt != nil {
            HStack(spacing: 8) {
                if let due = file.metadata?.dueAt {
                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.glowPrimary)
                }
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.surface))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        TextField("Title", text: $draftTitle)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(palette.textPrimary)
            .textInputAutocapitalization(.sentences)

        TextEditor(text: $draftBody)
            .font(.system(size: 15))
            .foregroundStyle(palette.textPrimary)
            .frame(minHeight: 220, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))

        TextField("tags, comma, separated", text: $draftTagsText)
            .font(.system(size: 14))
            .foregroundStyle(palette.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))

        Toggle(isOn: $draftIsTodo) {
            Text("Make this a todo").lvFont(.body).foregroundStyle(palette.textPrimary)
        }
        .tint(palette.glowPrimary)

        if draftIsTodo {
            Toggle(isOn: $draftDone) {
                Text("Done").lvFont(.body).foregroundStyle(palette.textPrimary)
            }
            .tint(palette.glowPrimary)

            Toggle(isOn: $draftHasDue) {
                Text("Due date + reminder").lvFont(.body).foregroundStyle(palette.textPrimary)
            }
            .tint(palette.glowPrimary)

            if draftHasDue {
                DatePicker("Due", selection: $draftDueAt, in: Date()...)
                    .datePickerStyle(.compact)
                    .tint(palette.glowPrimary)
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftBody = rawText ?? ""
        draftTitle = file.metadata?.title ?? ""
        draftTagsText = (file.metadata?.tags ?? []).joined(separator: ", ")
        draftIsTodo = file.metadata?.isTodo ?? false
        draftDone = file.metadata?.done ?? false
        if let due = file.metadata?.dueAt {
            draftHasDue = true
            draftDueAt = due
        } else {
            draftHasDue = false
        }
        isEditing = true
    }

    private func currentMetadata() -> VaultNoteMetadataDTO {
        let tags = draftTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return VaultNoteMetadataDTO(
            title: title.isEmpty ? nil : title,
            tags: tags.isEmpty ? nil : tags,
            isTodo: draftIsTodo ? true : nil,
            done: draftIsTodo ? draftDone : nil,
            dueAt: (draftIsTodo && draftHasDue) ? draftDueAt : nil,
        )
    }

    private func save() async {
        guard let uploadClient, let data = draftBody.data(using: .utf8) else { return }
        saving = true
        defer { saving = false }
        let metadata = currentMetadata()
        do {
            _ = try await uploadClient.uploadNote(
                data: data,
                contentType: "text/markdown",
                relativePath: file.path,
                spaceID: file.spaceId,
                metadata: metadata,
            )
            rawText = draftBody
            // Reschedule the local reminder off the new due/done state.
            await NoteReminderScheduler.shared.reschedule(
                noteID: file.id,
                title: metadata.title ?? displayTitle,
                dueAt: metadata.dueAt,
                done: metadata.done ?? false,
            )
            isEditing = false
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteNote() async {
        do {
            try await vaultClient.deleteFile(relativePath: file.path)
            await NoteReminderScheduler.shared.cancel(noteID: file.id)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let (data, contentType) = try await vaultClient.readFile(relativePath: file.path)
            let isText = contentType.hasPrefix("text/")
                || contentType.contains("markdown")
                || contentType == "application/json"
            guard isText else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            self.rawText = text
            self.isMarkdown = contentType.contains("markdown") || file.path.hasSuffix(".md")
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
