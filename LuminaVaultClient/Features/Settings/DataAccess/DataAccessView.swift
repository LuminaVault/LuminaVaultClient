// LuminaVaultClient/LuminaVaultClient/Features/Settings/DataAccess/DataAccessView.swift
//
// Apple Ecosystem Integration P0 — the control surface. One row per Apple
// data domain with an allow/disallow toggle (the LuminaVault consent that
// gates sync AND Hermes tool access, enforced server-side) plus an "Allow
// Hermes to make changes" sub-toggle for write-capable domains. Backed by
// GET/PUT /v1/apple/consent.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class DataAccessViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var consents: [AppleConsentDTO] = []
    private let client: AppleConsentClientProtocol

    init(client: AppleConsentClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            consents = try await client.get().consents
            state = .loaded
        } catch {
            state = .failed("Couldn't load your data-access settings.")
        }
    }

    func consent(_ domain: AppleDataDomain) -> AppleConsentDTO {
        consents.first { $0.domain == domain } ?? AppleConsentDTO(domain: domain, allowed: false)
    }

    func setAllowed(_ domain: AppleDataDomain, _ allowed: Bool) {
        apply(AppleConsentUpdateRequest(domain: domain, allowed: allowed, allowWrites: consent(domain).allowWrites))
    }

    func setWrites(_ domain: AppleDataDomain, _ writes: Bool) {
        apply(AppleConsentUpdateRequest(domain: domain, allowed: consent(domain).allowed, allowWrites: writes))
    }

    private func apply(_ request: AppleConsentUpdateRequest) {
        // Optimistic local update, then reconcile with the server snapshot.
        upsertLocal(domain: request.domain, allowed: request.allowed, writes: request.allowWrites ?? consent(request.domain).allowWrites)
        Task { [weak self] in
            guard let self else { return }
            if let response = try? await self.client.update(request) {
                self.consents = response.consents
            }
        }
    }

    private func upsertLocal(domain: AppleDataDomain, allowed: Bool, writes: Bool) {
        let dto = AppleConsentDTO(domain: domain, allowed: allowed, allowWrites: writes, lastSyncAt: consent(domain).lastSyncAt)
        if let i = consents.firstIndex(where: { $0.domain == domain }) { consents[i] = dto }
        else { consents.append(dto) }
    }
}

struct DataAccessView: View {
    @Environment(\.lvPalette) private var palette
    @State var vm: DataAccessViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Data Access")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let message):
            Text(message).font(.system(size: 13)).foregroundStyle(Color.lvTextMuted).padding()
        case .loaded:
            ScrollView {
                VStack(spacing: 12) {
                    header
                    ForEach(AppleDataDomain.allCases, id: \.self) { domain in
                        DomainRow(
                            meta: AppleDomainMeta.of(domain),
                            consent: vm.consent(domain),
                            onAllowed: { vm.setAllowed(domain, $0) },
                            onWrites: { vm.setWrites(domain, $0) },
                        )
                    }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    private var header: some View {
        Text("Choose what Lumina can read and act on. These are independent of iOS permissions — turning a source off here stops syncing and hides it from Hermes, and deletes the synced copy.")
            .font(.system(size: 13))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("iOS may also ask for permission the first time a source is used. Manage system permissions in Settings ▸ Privacy & Security.")
            .font(.system(size: 11))
            .foregroundStyle(Color.lvTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

private struct DomainRow: View {
    @Environment(\.lvPalette) private var palette
    let meta: AppleDomainMeta
    let consent: AppleConsentDTO
    let onAllowed: (Bool) -> Void
    let onWrites: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: meta.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.glowPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(meta.blurb).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    // Shown only for synced domains that have actually run a
                    // sync (last_sync_at stamped server-side); on-demand
                    // device-RPC domains (files, location) never set it.
                    if consent.allowed, let synced = consent.lastSyncAt {
                        Text("Synced \(synced, format: .relative(presentation: .named))")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary.opacity(0.8))
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { consent.allowed }, set: onAllowed))
                    .labelsHidden()
                    .tint(palette.primary)
            }
            if consent.allowed, meta.writeCapable {
                Divider().overlay(palette.textSecondary.opacity(0.2))
                HStack {
                    Text("Allow Hermes to make changes")
                        .font(.system(size: 13)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(get: { consent.allowWrites }, set: onWrites))
                        .labelsHidden()
                        .tint(palette.primary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).stroke(palette.glowPrimary.opacity(0.15), lineWidth: 1))
    }
}

/// Client-side display metadata per Apple domain.
private struct AppleDomainMeta {
    let title: String
    let icon: String
    let blurb: String
    let writeCapable: Bool

    static func of(_ domain: AppleDataDomain) -> AppleDomainMeta {
        switch domain {
        case .health: AppleDomainMeta(title: "Health", icon: "heart.fill", blurb: "Sleep, activity, heart rate", writeCapable: false)
        case .calendar: AppleDomainMeta(title: "Calendar", icon: "calendar", blurb: "Your events", writeCapable: true)
        case .reminders: AppleDomainMeta(title: "Reminders", icon: "checklist", blurb: "Reminders & tasks", writeCapable: true)
        case .photos: AppleDomainMeta(title: "Photos", icon: "photo.on.rectangle", blurb: "On-device analysis (text, labels)", writeCapable: false)
        case .location: AppleDomainMeta(title: "Location", icon: "location.fill", blurb: "Recent places & visits", writeCapable: false)
        case .files: AppleDomainMeta(title: "Files", icon: "folder.fill", blurb: "Documents you choose", writeCapable: false)
        }
    }
}
