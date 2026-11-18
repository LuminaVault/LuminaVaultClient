// LuminaVaultClient/LuminaVaultClient/Features/Vault/NotePropertiesSection.swift
// Backlog E8.5: a note's frontmatter as a read-only list under its title, in
// place of the tags/due badges. Editing properties is post-1.0 on iOS; the
// web edits them.
import SwiftUI

struct NotePropertiesSection: View {
    @Environment(\.lvPalette) private var palette

    let rows: [NotePropertyRow]
    /// The server could not parse the note's frontmatter.
    let parseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let parseError {
                Label("This note’s properties can’t be read: \(parseError)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 96, alignment: .leading)
                        .lineLimit(1)
                    NotePropertyValueView(row: row)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface.opacity(0.6)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Properties")
    }
}

/// One value, drawn for its type: chips for lists, a check for checkboxes, a
/// link for urls, text otherwise.
struct NotePropertyValueView: View {
    @Environment(\.lvPalette) private var palette
    let row: NotePropertyRow

    var body: some View {
        switch row.value {
        case .null:
            Text("Empty").font(.system(size: 13)).foregroundStyle(palette.textSecondary.opacity(0.7))
        case let .bool(on) where row.kind == .checkbox:
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .foregroundStyle(on ? palette.glowPrimary : palette.textSecondary)
                .accessibilityLabel(on ? "Yes" : "No")
        case let .list(items):
            if items.isEmpty {
                Text("Empty").font(.system(size: 13)).foregroundStyle(palette.textSecondary.opacity(0.7))
            } else {
                chips(items)
            }
        default:
            if row.kind == .url, let url = VaultPropertyDisplay.link(row.value) {
                Link(VaultPropertyDisplay.text(row.value, kind: row.kind), destination: url)
                    .font(.system(size: 13))
                    .lineLimit(1)
            } else {
                Text(VaultPropertyDisplay.text(row.value, kind: row.kind))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    private func chips(_ items: [VaultPropertyValue]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chipItems(items) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { chipItems(items) }
            }
        }
    }

    private func chipItems(_ items: [VaultPropertyValue]) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Text(VaultPropertyDisplay.text(item, kind: .text))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(palette.surface))
                .foregroundStyle(palette.textSecondary)
        }
    }
}
