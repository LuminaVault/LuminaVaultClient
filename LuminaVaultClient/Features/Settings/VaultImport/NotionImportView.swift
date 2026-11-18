// LuminaVaultClient/LuminaVaultClient/Features/Settings/VaultImport/NotionImportView.swift
//
// Settings → Import Vault → Import from Notion (backlog E7.4). Pick the export
// ZIP in Files, check it (a dry run), read the report, then import. The logic
// is in `NotionImportViewModel`; this is the form around it.

import SwiftUI
import UniformTypeIdentifiers

struct NotionImportView: View {
    @State private var viewModel: NotionImportViewModel
    @State private var picking = false
    /// The work the user last asked for. `.task(id:)` runs it, so leaving the
    /// screen cancels an upload instead of orphaning it.
    @State private var request: Request?

    private struct Request: Equatable {
        enum Kind: Equatable {
            case pick(URL)
            case check
            case runImport
        }

        let id = UUID()
        let kind: Kind
    }

    init(client: VaultImportClientProtocol) {
        _viewModel = State(initialValue: NotionImportViewModel(client: client))
    }

    var body: some View {
        Form {
            fileSection
            if let message = viewModel.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
            }
            if viewModel.phase != .idle, viewModel.phase != .reading, viewModel.phase != .done {
                destinationSection
                actionSection
            }
            if let report = viewModel.report {
                NotionImportReportSections(report: report)
            }
            if viewModel.phase == .done {
                Section {
                    Button("Import another export") { viewModel.reset() }
                }
            }
        }
        .navigationTitle("Import from Notion")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    request = Request(kind: .pick(url))
                }
            case let .failure(error):
                viewModel.pickFailed(error)
            }
        }
        .task(id: request) {
            guard let request else { return }
            switch request.kind {
            case let .pick(url): await viewModel.pick(url)
            case .check: await viewModel.check()
            case .runImport: await viewModel.runImport()
            }
            // `.task(id:)` runs again whenever the screen reappears (a tab
            // switch and back). A finished or cancelled request must not be
            // replayed: that would upload, or import, a second time.
            if self.request == request {
                self.request = nil
            }
        }
    }

    @ViewBuilder private var fileSection: some View {
        switch viewModel.phase {
        case .idle:
            Section {
                Button {
                    picking = true
                } label: {
                    Label("Choose Notion export…", systemImage: "doc.zipper")
                }
            } footer: {
                Text(
                    "In Notion, export as Markdown & CSV with subpages included, then pick the ZIP here. "
                        + "Pages become notes in one Space, links between them keep working, "
                        + "and databases become notes with properties. Up to 200 MB."
                )
            }
        case .reading:
            Section {
                HStack(spacing: 12) { ProgressView(); Text("Reading file…") }
            }
        default:
            Section("Export") {
                HStack {
                    Text(viewModel.fileName ?? "export.zip").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(viewModel.fileSizeText).foregroundStyle(.secondary).monospacedDigit()
                }
                if viewModel.phase != .done {
                    Button("Choose another file…") { picking = true }
                        .disabled(viewModel.isBusy)
                }
            }
        }
    }

    private var destinationSection: some View {
        Section {
            TextField("Space name", text: $viewModel.spaceName)
                .disabled(viewModel.isBusy)
        } header: {
            Text("Space")
        } footer: {
            Text("Everything in the export goes into this Space. Notes already there are kept as they are.")
        }
    }

    @ViewBuilder private var actionSection: some View {
        switch viewModel.phase {
        case .checking:
            progressSection(working: "Checking the export…")
        case .importing:
            progressSection(working: "Importing… this can take a few minutes")
        default:
            Section {
                Button("Check") { request = Request(kind: .check) }
                    .disabled(!viewModel.canCheck)
                Button("Import") { request = Request(kind: .runImport) }
                    .disabled(!viewModel.canImport)
            } footer: {
                Text(
                    viewModel.canImport
                        ? "Nothing has been written yet. Import does what the report below says."
                        : "Check reads the export and reports what an import would do, without writing anything."
                )
            }
        }
    }
}

private extension NotionImportView {
    /// "Uploading…" with a bar while the ZIP goes up, then the wait for the
    /// server, which answers only once it has gone through the whole export.
    func progressSection(working: String) -> some View {
        Section {
            if viewModel.isWaitingForServer {
                HStack(spacing: 12) { ProgressView(); Text(working) }
            } else {
                ProgressView(value: viewModel.uploadProgress ?? 0)
                Text("Uploading… \(Int((viewModel.uploadProgress ?? 0) * 100))%")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Keep this screen open until it finishes.")
        }
    }
}

/// The plain report, the same sections for the dry run and the import.
private struct NotionImportReportSections: View {
    let report: VaultNotionImportReport

    private static let listLimit = 50

    var body: some View {
        Section {
            row("Pages", report.pages)
            row("Databases", report.databases)
            row("Database rows", report.rows)
            row("Attachments", report.attachments)
            if !report.dryRun {
                row("Written", report.written)
            }
            row(report.dryRun ? "Would be skipped" : "Skipped", report.skipped)
            row(report.dryRun ? "Can't be imported" : "Failed", report.failed)
        } header: {
            Text(report.dryRun ? "What an import would do" : "Imported")
        } footer: {
            if !report.dryRun, let slug = report.spaceSlug {
                Text("The notes are in the Space \u{201C}\(slug)\u{201D}.")
            }
        }

        Section("Links") {
            row("Resolved", report.links.resolved)
            row("External", report.links.external)
            row("Unresolved", report.links.unresolved)
            ForEach(Array(report.links.unresolvedList.prefix(Self.listLimit).enumerated()), id: \.offset) { _, link in
                detail(link.target ?? "Unknown target", "in \(link.page ?? "unknown page")")
            }
        }

        if !report.warnings.isEmpty {
            Section("Warnings") {
                ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).font(.footnote)
                }
            }
        }

        if !report.views.isEmpty {
            Section(report.dryRun ? "Views to create" : "Views") {
                ForEach(Array(report.views.enumerated()), id: \.offset) { _, view in
                    detail(view.name ?? "Untitled", view.folder ?? "")
                }
            }
        }

        if !report.columns.isEmpty {
            Section("Database columns") {
                ForEach(Array(report.columns.prefix(Self.listLimit).enumerated()), id: \.offset) { _, column in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.name ?? "Untitled").font(.footnote)
                            Text(column.database ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(column.type ?? "").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                more(report.columns.count)
            }
        }

        if !report.collisions.isEmpty {
            Section("Renamed to avoid a clash") {
                ForEach(Array(report.collisions.prefix(Self.listLimit).enumerated()), id: \.offset) { _, collision in
                    detail(collision.from ?? "", "saved as \(collision.to ?? "")")
                }
                more(report.collisions.count)
            }
        }

        let problems = report.files.filter { NotionImportReportSections.problemLabels[$0.status ?? ""] != nil }
        if !problems.isEmpty {
            Section("Files to check") {
                ForEach(Array(problems.prefix(Self.listLimit).enumerated()), id: \.offset) { _, file in
                    detail(file.entry ?? file.savedPath ?? "", Self.problemLabels[file.status ?? ""] ?? "")
                }
                more(problems.count)
            }
        }
    }

    /// The per-file outcomes worth a line; the rest are counted above.
    private static let problemLabels: [String: String] = [
        "failed": "Could not be imported",
        "tooLarge": "Too large, left out",
        "unsupported": "Not a supported file type, left out",
        "exists": "Already in LuminaVault; the existing note was kept",
    ]

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func detail(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder private func more(_ count: Int) -> some View {
        if count > Self.listLimit {
            Text("and \(count - Self.listLimit) more").font(.caption).foregroundStyle(.secondary)
        }
    }
}
