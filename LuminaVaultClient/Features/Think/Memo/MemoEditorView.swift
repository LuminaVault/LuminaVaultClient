// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/MemoEditorView.swift
// HER-37: Memo creation screen — topic + optional hint, "Save as Memo"
// CTA, Lumina suggestions sidebar (empty state at scaffold).
import SwiftUI

struct MemoEditorView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: MemoEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topicField
                    hintField
                    LuminaSuggestionsSidebar()
                    if case let .failed(message) = vm.phase {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .lvBackground()
            .navigationTitle("New Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await vm.save()
                            if case .saved = vm.phase { dismiss() }
                        }
                    } label: {
                        if vm.isBusy {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(!vm.canSave)
                }
            }
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topic")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField("Topic", text: $vm.topic, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.lvGlass)
                )
        }
    }

    private var hintField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hint (optional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField("Anything Lumina should keep in mind…", text: $vm.hint, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.lvGlass)
                )
        }
    }
}
