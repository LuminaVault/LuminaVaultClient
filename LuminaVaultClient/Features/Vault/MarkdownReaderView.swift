// LuminaVaultClient/LuminaVaultClient/Features/Vault/MarkdownReaderView.swift
// HER-105: in-app reader for a single vault file. Markdown gets rendered
// via SwiftUI text with Obsidian-compatible wikilink routing. Binary files
// fall through to a placeholder.
// HER-Notes: text/markdown files are now editable like Apple Notes — edit
// the body, set a title + tags, promote to a smart todo (done + due date
// with a local reminder), and delete. Saving re-PUTs the note so the server
// re-embeds its recall memory in place (no separate memory call).
import Algorithms
import LuminaVaultShared
import SwiftUI
import UIKit

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
    /// Backlog E5.3: the cursor in the body editor, for `[[` suggestions.
    @State private var draftSelection: TextSelection?
    @State private var linkSuggestions: WikilinkSuggestionModel?
    /// Backlog E5.4: the formatting bar shows only while the body has focus.
    @FocusState private var bodyFocused: Bool
    @State private var draftTitle: String = ""
    @State private var draftTagsText: String = ""
    @State private var draftIsTodo = false
    @State private var draftDone = false
    @State private var draftHasDue = false
    @State private var draftDueAt: Date = .now.addingTimeInterval(3600)
    @State private var saving = false
    @State private var showDeleteConfirm = false
    /// sha256 of the version this reader loaded or last saved (E5.4).
    @State private var baseSHA: String?
    @State private var showConflict = false
    /// Backlog E4.5: the version history sheet.
    @State private var showHistory = false

    // Backlog E2.2 — Linked from / Links to
    @State private var linkGroups: NoteLinkGroups?
    @State private var linksLoading = false
    @State private var linksError: String?
    @State private var linkedNote: VaultFileDTO?
    @State private var linkOpenError: String?

    // Backlog E8.5 — the note's frontmatter, read-only. nil while properties
    // are off on the server or the note has none.
    @State private var propertyRows: [NotePropertyRow]?
    @State private var propertiesError: String?

    /// The properties section replaces the tags/due badges and the raw
    /// frontmatter block in the rendered note.
    private var showsProperties: Bool {
        (propertyRows?.isEmpty == false) || propertiesError != nil
    }

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
            // Reading measure: ~70 characters. A no-op on iPhone portrait;
            // keeps lines readable on iPad and in landscape.
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
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
        // Separate from `load()` so the note body never waits on its links.
        .task(id: isMarkdown) { if isMarkdown { await loadLinks() } }
        .task(id: isMarkdown) { if isMarkdown { await loadProperties() } }
        .navigationDestination(isPresented: Binding(
            get: { linkedNote != nil },
            set: { if !$0 { linkedNote = nil } }
        )) {
            if let linkedNote {
                MarkdownReaderView(
                    file: linkedNote,
                    vaultClient: vaultClient,
                    memoryClient: memoryClient,
                    uploadClient: uploadClient
                )
            }
        }
        .sheet(isPresented: $showHistory) {
            NoteHistoryView(
                viewModel: NoteHistoryViewModel(vaultClient: vaultClient, path: file.path, currentSHA: baseSHA),
                canRestore: uploadClient != nil
            ) { _ in
                Task {
                    await load()
                    if isMarkdown {
                        await loadLinks()
                        await loadProperties()
                    }
                }
            }
        }
        .alert("This note changed on another device", isPresented: $showConflict) {
            Button("Keep my version") { Task { await save(overwrite: true) } }
            Button("Copy mine and load theirs") { Task { await copyDraftAndReload() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone saved it after you opened it. Keep yours to replace theirs, or load theirs. Your text is copied so you can paste it back.")
        }
        .alert(
            "Note unavailable",
            isPresented: Binding(
                get: { linkOpenError != nil },
                set: { if !$0 { linkOpenError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { linkOpenError = nil }
        } message: {
            Text(linkOpenError ?? "")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
        }
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
                .lvFont(.title)
                .foregroundStyle(palette.textPrimary)
                .strikethrough(file.metadata?.done == true, color: palette.textSecondary)
        }

        if showsProperties {
            NotePropertiesSection(rows: propertyRows ?? [], parseError: propertiesError)
        } else {
            metaBadges
        }

        Divider().background(palette.surfaceStroke)

        if isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else if let error {
            Text(error).font(.system(size: 13)).foregroundStyle(.red.opacity(0.85))
        } else if let rawText, isMarkdown {
            WikilinkMarkdownView(
                markdown: showsProperties && propertiesError == nil ? NoteFrontmatter.strip(rawText) : rawText,
                vaultClient: vaultClient,
                memoryClient: memoryClient
            )
            NoteLinksSection(
                groups: linkGroups,
                isLoading: linksLoading,
                error: linksError,
                onOpen: { path in Task { await openLinkedNote(path) } }
            )
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
        // `ForEach(tags, id: \.self)` below needs unique elements; note
        // frontmatter can repeat a tag, and rendering "#work #work" is a bug
        // regardless of how it is keyed.
        let tags = Array((file.metadata?.tags ?? []).uniqued())
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

        TextEditor(text: $draftBody, selection: $draftSelection)
            .font(.system(size: 15))
            .foregroundStyle(palette.textPrimary)
            .frame(minHeight: 220, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
            .onChange(of: draftBody) { refreshLinkSuggestions() }
            .onChange(of: draftSelection) { refreshLinkSuggestions() }
            .focused($bodyFocused)
            .toolbar {
                if bodyFocused && isMarkdown {
                    ToolbarItemGroup(placement: .keyboard) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 18) {
                                ForEach(MarkdownFormatting.Action.allCases) { action in
                                    Button { format(action) } label: {
                                        Image(systemName: action.systemImage)
                                    }
                                    .accessibilityLabel(action.title)
                                }
                            }
                        }
                        Button("Done") { bodyFocused = false }
                    }
                }
            }

        if let linkSuggestions, !linkSuggestions.suggestions.isEmpty {
            WikilinkSuggestionsRow(suggestions: linkSuggestions.suggestions) { acceptLinkSuggestion($0) }
        }

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

    /// The cursor when nothing is selected; nil for a range or a stale index.
    private var draftCursor: String.Index? {
        guard let draftSelection, case let .selection(range) = draftSelection.indices,
              range.isEmpty, range.lowerBound <= draftBody.endIndex,
              range.lowerBound.samePosition(in: draftBody) != nil
        else { return nil }
        return range.lowerBound
    }

    /// Backlog E5.4: applies a toolbar action to the body at the selection.
    /// Without a known selection it acts at the end of the note.
    private func format(_ action: MarkdownFormatting.Action) {
        let body = draftBody
        var selection = MarkdownFormatting.Selection.cursor(body.count)
        if let draftSelection, case let .selection(range) = draftSelection.indices,
           range.upperBound <= body.endIndex,
           range.lowerBound.samePosition(in: body) != nil, range.upperBound.samePosition(in: body) != nil
        {
            selection = .init(
                lower: body.distance(from: body.startIndex, to: range.lowerBound),
                upper: body.distance(from: body.startIndex, to: range.upperBound)
            )
        }
        let (text, out) = MarkdownFormatting.apply(action, to: body, selection: selection)
        draftBody = text
        let lower = text.index(text.startIndex, offsetBy: out.lower)
        let upper = text.index(text.startIndex, offsetBy: out.upper)
        draftSelection = out.lower == out.upper
            ? TextSelection(insertionPoint: lower)
            : TextSelection(range: lower ..< upper)
    }

    private func refreshLinkSuggestions() {
        linkSuggestions?.update(text: draftBody, cursor: draftCursor)
    }

    private func acceptLinkSuggestion(_ suggestion: WikilinkSuggestionModel.Suggestion) {
        guard let cursor = draftCursor,
              let (text, offset) = linkSuggestions?.accept(suggestion, text: draftBody, cursor: cursor)
        else { return }
        draftBody = text
        draftSelection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset))
    }

    private func beginEditing() {
        linkSuggestions = isMarkdown ? WikilinkSuggestionModel(vaultClient: vaultClient) : nil
        draftSelection = nil
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

    /// `overwrite` skips the version check: the user chose to keep their
    /// version after a conflict.
    private func save(overwrite: Bool = false) async {
        guard let uploadClient, let data = draftBody.data(using: .utf8) else { return }
        saving = true
        defer { saving = false }
        let metadata = currentMetadata()
        do {
            // In place, at the note's own path: an upload would refile a
            // nested note (an imported `lore/people/ada.md`) as `lore/ada.md`.
            _ = try await uploadClient.replaceNote(
                data: data,
                contentType: "text/markdown",
                relativePath: file.path,
                metadata: metadata,
                ifMatch: overwrite ? nil : NoteVersion.ifMatch(baseSHA),
            )
            baseSHA = NoteVersion.sha256(data)
            rawText = draftBody
            // Reschedule the local reminder off the new due/done state.
            await NoteReminderScheduler.shared.reschedule(
                noteID: file.id,
                title: metadata.title ?? displayTitle,
                dueAt: metadata.dueAt,
                done: metadata.done ?? false,
            )
            isEditing = false
            // An edit can add or remove wikilinks, and change the frontmatter.
            await loadLinks()
            await loadProperties()
        } catch where NoteVersion.isConflict(error) {
            showConflict = true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Conflict, "load the other version": the draft goes to the clipboard so
    /// nothing typed is lost, then the reader shows what is on the server.
    private func copyDraftAndReload() async {
        UIPasteboard.general.string = draftBody
        isEditing = false
        await load()
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
            self.baseSHA = NoteVersion.sha256(data)
            self.isMarkdown = contentType.contains("markdown") || file.path.hasSuffix(".md")
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Backlog E8.5. Silent on failure: the note reads fine without them.
    private func loadProperties() async {
        do {
            guard let types = try await vaultClient.propertyTypes(),
                  let row = try await vaultClient.fileProperties(path: file.path)
            else {
                propertyRows = nil
                propertiesError = nil
                return
            }
            propertyRows = NotePropertyRow.rows(row.properties ?? [:], types: types)
            propertiesError = row.propertiesError
        } catch {
            propertyRows = nil
            propertiesError = nil
        }
    }

    private func loadLinks() async {
        linksLoading = true
        linksError = nil
        defer { linksLoading = false }
        do {
            linkGroups = NoteLinkGroups(try await vaultClient.documentLinks(vaultFileID: file.id))
        } catch {
            linksError = "Links are unavailable for this note."
        }
    }

    /// The links API returns paths; the reader needs the file row, so look
    /// the exact path up through the same search the wikilinks use.
    private func openLinkedNote(_ path: String) async {
        do {
            let response = try await vaultClient.listFiles(spaceSlug: nil, q: path, before: nil, after: nil, limit: 20)
            if let match = response.files.first(where: { $0.path == path }) {
                linkedNote = match
            } else {
                linkOpenError = "No note at \(path). It may have been moved or deleted."
            }
        } catch {
            linkOpenError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Backlog E5.3: notes (or headings) matching the `[[…` being typed. Tap one to
/// write the link.
private struct WikilinkSuggestionsRow: View {
    @Environment(\.lvPalette) private var palette
    let suggestions: [WikilinkSuggestionModel.Suggestion]
    let onPick: (WikilinkSuggestionModel.Suggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button { onPick(suggestion) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link").font(.system(size: 11))
                            Text(suggestion.label).font(.system(size: 14, weight: .medium))
                            if !suggestion.detail.isEmpty {
                                Text(suggestion.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityLabel(
                        suggestion.detail.isEmpty
                            ? "Link to \(suggestion.label)"
                            : "Link to \(suggestion.label) in \(suggestion.detail)"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Link suggestions")
    }
}
