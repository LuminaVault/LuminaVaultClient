// LuminaVaultClient/LuminaVaultClient/Features/Reflect/TopicInputSheet.swift
//
// HER-194 — modal that gathers the (optional) topic input before a
// reflection runs. Beliefs requires a topic; the other two skills
// accept an empty submission.

import SwiftUI

struct TopicInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    let skill: ReflectionSkill
    let onSubmit: (String?) -> Void

    @State private var topic: String = ""
    @FocusState private var topicFocused: Bool

    private var trimmed: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        if skill.topicRequired { return !trimmed.isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header

                TextField(skill.inputPlaceholder, text: $topic, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .textInputAutocapitalization(.sentences)
                    .focused($topicFocused)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Topic")

                if skill.topicRequired, trimmed.isEmpty {
                    Text("Topic is required.")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.85))
                }

                Spacer()

                Button {
                    onSubmit(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                } label: {
                    Text("Run reflection")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            palette.primary.opacity(isValid ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: 14),
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
            .padding(20)
            .lvBackground()
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { topicFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: skill.iconSystemName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(palette.glowPrimary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(skill.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}
