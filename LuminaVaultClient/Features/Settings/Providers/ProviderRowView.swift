// LuminaVaultClient/LuminaVaultClient/Features/Settings/Providers/ProviderRowView.swift
//
// HER-252 — single provider row. Three visual states keyed off the DTO:
//   Not configured → muted grey label.
//   Connected (verified)   → green checkmark + relative "Verified 3m ago".
//   Connected (unverified) → blue dot ("Saved — Test to verify").
//   Failure → orange triangle + last_failure_code.

import LuminaVaultShared
import SwiftUI

struct ProviderRowView: View {
    let provider: ProviderID
    let dto: ProviderCredentialDTO?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ProvidersPaneViewModel.displayName(for: provider))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let dto, dto.hasCredential else {
            return "Not configured"
        }
        if let failed = dto.lastFailureAt, let code = dto.lastFailureCode {
            return "Failed \(Self.relative.localizedString(for: failed, relativeTo: Date())) — \(code)"
        }
        if let verifiedAt = dto.verifiedAt {
            return "Verified \(Self.relative.localizedString(for: verifiedAt, relativeTo: Date()))"
        }
        return "Saved — tap Test to verify"
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let dto, dto.lastFailureAt != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let dto, dto.verifiedAt != nil {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else if let dto, dto.hasCredential {
            Circle().fill(.blue).frame(width: 8, height: 8)
        } else {
            EmptyView()
        }
    }
}
