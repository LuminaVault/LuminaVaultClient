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
            LVIconView(.magnifyingglass, tint: palette.textSecondary)
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
                    LVIconView(.xmarkCircleFill, tint: Color.lvTextMuted, label: "Clear search")
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
                // One `LazyVStack` with `Section`s rather than a `VStack` of
                // nested `VStack`s: rows inside a section of a lazy stack are
                // built on demand, whereas the previous per-section `VStack`
                // built every hit up front.
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let summary = vm.memorySummary, !summary.isEmpty {
                        summaryCard(summary)
                    }
                    if !vm.memoryHits.isEmpty {
                        Section {
                            ForEach(vm.memoryHits) { hit in
                                memoryRow(hit)
                            }
                        } header: {
                            sectionHeader("Memories")
                        }
                    }
                    if !vm.fileHits.isEmpty {
                        Section {
                            ForEach(vm.fileHits) { file in
                                NavigationLink {
                                    MarkdownReaderView(file: file, vaultClient: vaultClient, memoryClient: memoryClient)
                                } label: {
                                    fileRow(file)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            sectionHeader("Files")
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, weight: .bold))
            .foregroundStyle(Color.lvTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Restores the 16pt gap between groups that the old nested
            // `VStack(spacing: 16)` provided; the lazy stack itself now runs
            // at the 8pt row rhythm.
            .padding(.top, LVSpacing.sm)
    }

    private func memoryRow(_ hit: QueryHitDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.content)
                .font(.system(size: 13))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
            if let createdAt = hit.createdAt {
                Text(createdAt, style: .relative)
                    .font(.system(.caption2))
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
            LVIconView(.questionmarkAppDashed, size: 40, tint: Color.lvTextMuted)
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
