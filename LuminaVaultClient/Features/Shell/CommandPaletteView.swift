// LuminaVaultClient/LuminaVaultClient/Features/Shell/CommandPaletteView.swift
//
// A keyboard route to anywhere in the app, on Cmd-K.
//
// Keyboard-first on purpose: on a phone the tab bar already is the fastest
// way to a destination, and a palette earns its place on an iPad with a
// hardware keyboard, where reaching for the screen is the slow path. The
// arrows move the highlight and Return runs it, as on the web.

import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let entries: [CommandPaletteMatcher.Entry]
    let onRun: (CommandPaletteMatcher.Entry) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var results: [CommandPaletteMatcher.Entry] {
        CommandPaletteMatcher.filter(entries, query)
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    Text("Nothing matches that.")
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        run(entry)
                    } label: {
                        HStack {
                            Text(entry.label).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(entry.group)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(index == highlighted ? palette.surface : Color.clear)
                    .accessibilityAddTraits(index == highlighted ? .isSelected : [])
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Go to…")
            .searchFocused($fieldFocused)
            .onSubmit(of: .search) {
                if results.indices.contains(highlighted) { run(results[highlighted]) }
            }
            .onKeyPress(.downArrow) {
                guard !results.isEmpty else { return .ignored }
                highlighted = (highlighted + 1) % results.count
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !results.isEmpty else { return .ignored }
                highlighted = (highlighted - 1 + results.count) % results.count
                return .handled
            }
            // Any change to the list can leave the highlight past the end,
            // which would make Return do nothing with a row visibly selected.
            .onChange(of: query) { _, _ in highlighted = 0 }
            .navigationTitle("Go to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func run(_ entry: CommandPaletteMatcher.Entry) {
        dismiss()
        onRun(entry)
    }
}
