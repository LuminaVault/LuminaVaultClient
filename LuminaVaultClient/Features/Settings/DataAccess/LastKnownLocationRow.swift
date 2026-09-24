// LuminaVaultClient/LuminaVaultClient/Features/Settings/DataAccess/LastKnownLocationRow.swift
//
// Muse Stage C — Settings → Data Access → the location fix the server kept.
// A scheduled job (the 07:00 weather check) needs a place while the phone is
// asleep, so the server keeps the last live fix: one fix, overwritten, never
// a history. This row shows it and lets the user forget it
// (GET / DELETE /v1/me/location).

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class LastKnownLocationViewModel {
    enum State: Equatable, Sendable {
        case loading
        case ready(LastKnownLocationResponse)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    private(set) var lastError: String?

    private let client: any LastKnownLocationClientProtocol

    init(client: any LastKnownLocationClientProtocol) {
        self.client = client
    }

    var location: LastKnownLocationResponse? {
        if case let .ready(location) = state, location.cached { return location }
        return nil
    }

    /// "Lisbon", or the coordinates when the server could not name the place.
    var placeText: String? { location.flatMap(Self.placeText) }

    nonisolated static func placeText(_ location: LastKnownLocationResponse) -> String? {
        guard location.cached else { return nil }
        if let place = location.place?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            return place
        }
        if let lat = location.latitude, let lon = location.longitude {
            return String(format: "%.2f, %.2f", lat, lon)
        }
        return "Unnamed place"
    }

    func load() async {
        if case .ready = state {} else { state = .loading }
        do {
            state = .ready(try await client.get())
        } catch is CancellationError {
            return
        } catch {
            state = .failed("Couldn't load your saved location.")
        }
    }

    func forget() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await client.forget()
            state = .ready(LastKnownLocationResponse(cached: false))
        } catch {
            lastError = "Couldn't forget your location. Try again."
        }
    }
}

struct LastKnownLocationRow: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: LastKnownLocationViewModel

    init(viewModel: LastKnownLocationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.glowPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last known location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    detail
                }
                Spacer(minLength: 0)
            }
            Text("Kept so scheduled tasks, like a morning weather check, still work while your phone is asleep. One place, replaced each time — never a history.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.location != nil {
                Divider().overlay(palette.textSecondary.opacity(0.2))
                Button(role: .destructive) {
                    Task { await viewModel.forget() }
                } label: {
                    Text("Forget location")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: LVSize.tapTarget)
                }
                .disabled(viewModel.isWorking)
            }
            if let error = viewModel.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).stroke(palette.glowPrimary.opacity(0.15), lineWidth: 1))
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().controlSize(.small)
        case let .failed(message):
            Text(message).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        case .ready:
            if let place = viewModel.placeText {
                Text(place)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textPrimary)
                if let captured = viewModel.location?.capturedAt {
                    Text("Captured \(captured, format: .relative(presentation: .named))")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                }
            } else {
                Text("Nothing kept.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}
