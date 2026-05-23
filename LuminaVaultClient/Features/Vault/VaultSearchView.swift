// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultSearchView.swift
// HER-105: full-screen search sheet wired off the Spaces tab top bar.
// Single text field; on submit, fires the parallel memory + filename
// queries and renders both sections inline. Filename hits push the
// Markdown reader; memory hits show the synthesised summary + a list
// of supporting snippets (read-only for now — tapping a memory snippet
// pushes the reader if the memory has a source vault file, otherwise
// is inert).
import SwiftUI

struct VaultSearchView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: VaultSearchViewModel
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .lvBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textSecondary)
            TextField("Ask Lumina or find a file…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.search)
                .onSubmit { Task { await vm.run() } }
            if !vm.query.isEmpty {
                Button {
                    vm.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.lvGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(palette.surfaceStroke, lineWidth: 1),
                ),
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().controlSize(.large).padding(.top, 40)
            Spacer()
        } else if vm.memoryHits.isEmpty && vm.fileHits.isEmpty && !vm.query.isEmpty {
            empty
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = vm.memorySummary, !summary.isEmpty {
                        summaryCard(summary)
                    }
                    if !vm.memoryHits.isEmpty {
                        section(title: "Memories") {
                            ForEach(vm.memoryHits) { hit in
                                memoryRow(hit)
                            }
                        }
                    }
                    if !vm.fileHits.isEmpty {
                        section(title: "Files") {
                            ForEach(vm.fileHits) { file in
                                NavigationLink {
                                    MarkdownReaderView(file: file, vaultClient: vaultClient, memoryClient: memoryClient)
                                } label: {
                                    fileRow(file)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lumina says")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.primary)
            Text(summary)
                .font(.system(size: 14))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.lvGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(palette.surfaceStroke, lineWidth: 1),
                ),
        )
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.lvTextMuted)
                .padding(.bottom, 2)
            rows()
        }
    }

    private func memoryRow(_ hit: QueryHitDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.content)
                .font(.system(size: 13))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
            if let createdAt = hit.createdAt {
                Text(createdAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.lvGlass),
        )
    }

    private func fileRow(_ file: VaultFileDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((file.path as NSString).lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(file.path)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.lvGlass),
        )
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 40))
                .foregroundStyle(Color.lvTextMuted)
            Text("Nothing found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Try a different word, or capture more memories first.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 40)
    }
}
