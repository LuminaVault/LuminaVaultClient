// LuminaVaultClient/LuminaVaultClient/Features/KB/MemoryReviewSheet.swift
// HER-108 / HER-290 — modal sheet listing the memories the latest kb-compile
// just saved, with approve / reject affordances. Drives PATCH /v1/memory/{id}.
import LuminaVaultShared
import SwiftUI

struct MemoryReviewSheet: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let memories: [MemoryDTO]
    let onApprove: (MemoryDTO) async -> Void
    let onReject: (MemoryDTO) async -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundBase.ignoresSafeArea()
                // Deliberately a `ScrollView` + `LazyVStack` of cards rather
                // than a `List` with `.swipeActions`. A kb-compile run can
                // save an unbounded number of memories, so the stack has to be
                // lazy — but approve/reject must stay *visible*. This sheet
                // exists so the user consciously accepts or rejects each item,
                // reject is destructive and sticky ("Rejected items stay
                // rejected on future syncs"), and swipe actions are a hidden
                // affordance with no confirmation. Visible buttons are also
                // announced in reading order by VoiceOver, where swipe actions
                // are only reachable through the actions rotor.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Review what Hermes learned")
                            .font(.system(size: 20, weight: .heavy))
                            .padding(.horizontal, 4)
                        Text("Approve to keep, reject to forget. Rejected items stay rejected on future syncs.")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 4)

                        ForEach(memories, id: \.id) { memory in
                            MemoryReviewRow(
                                memory: memory,
                                onApprove: { Task { await onApprove(memory) } },
                                onReject: { Task { await onReject(memory) } },
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MemoryReviewRow: View {
    @Environment(\.lvPalette) private var palette
    let memory: MemoryDTO
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(memory.content)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)

            // Both were ~40pt tall (10pt padding around a 14pt label), under
            // the 44pt HIG minimum. The glyph sizes are unchanged; only the
            // frame grows.
            HStack(spacing: 8) {
                Button(role: .destructive, action: onReject) {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget)
                        .background(palette.surface)
                        .foregroundStyle(palette.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityHint("Forgets this memory. It stays rejected on future syncs.")
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: LVSize.tapTarget)
                        .background(LinearGradient(
                            colors: [palette.accent, palette.primary],
                            startPoint: .leading, endPoint: .trailing,
                        ))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityHint("Keeps this memory.")
            }
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
