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
            VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                Text(ProvidersPaneViewModel.displayName(for: provider))
                    .font(LVTypography.body.font)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(LVTypography.footnote.font)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
            LVIconView(.chevronRight, size: 13, tint: Color.secondary.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let dto, dto.hasCredential else {
            return "Not configured"
        }
        if provider == .xai && dto.kind == .oauth {
            return "Linked SuperGrok account"
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
            LVIconView(.exclamationmarkTriangleFill, tint: .orange)
        } else if let dto, dto.verifiedAt != nil {
            LVIconView(.checkmarkSealFill, tint: .green)
        } else if let dto, dto.hasCredential {
            Circle().fill(.blue).frame(width: 8, height: 8)
        } else {
            EmptyView()
        }
    }
}
