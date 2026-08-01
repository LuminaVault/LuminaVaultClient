// LuminaVaultClient/LuminaVaultClient/Features/Places/PlacesMapView.swift
//
// Every geo-anchored memory on one map — "where have I been thinking?".
//
// Built on data the app has been collecting since HER-207 and never showed.
// Read-only: it renders coordinates already stored on `MemoryDTO`, and never
// asks for a location fix. Capture-time location remains opt-in per capture via
// the toggle wired to `LocationService`.

import LuminaVaultShared
import MapKit
import SwiftUI

@MainActor
@Observable
final class PlacesViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var pins: [MemoryPin] = []

    private let client: any MemoryClientProtocol

    init(client: any MemoryClientProtocol) {
        self.client = client
    }

    func load(limit: Int = 200) async {
        state = .loading
        do {
            let memories = try await client.list(limit: limit, offset: 0).memories
            pins = memories.compactMap(MemoryPin.init(memory:))
            state = .loaded
        } catch {
            guard !error.isBenignCancellation else { return }
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// A region that frames every pin, or nil when there is nothing to show.
    var boundingRegion: MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        let lats = pins.map(\.coordinate.latitude)
        let lngs = pins.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // 1.4× padding so edge pins aren't flush against the frame, with a
        // floor so a single pin (zero span) still renders at a sane zoom.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLng - minLng) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct MemoryPin: Identifiable, Equatable {
    let id: UUID
    let title: String
    let placeName: String?
    let createdAt: Date?
    let coordinate: CLLocationCoordinate2D

    init?(memory: MemoryDTO) {
        guard let lat = memory.lat, let lng = memory.lng else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        self.id = memory.id
        self.title = memory.content
        self.placeName = memory.placeName
        self.createdAt = memory.createdAt
        self.coordinate = coordinate
    }

    /// First line of the memory, trimmed — full note bodies make useless labels.
    var shortTitle: String {
        let firstLine = title.split(separator: "\n").first.map(String.init) ?? title
        return firstLine.count > 42 ? String(firstLine.prefix(42)) + "…" : firstLine
    }

    static func == (lhs: MemoryPin, rhs: MemoryPin) -> Bool { lhs.id == rhs.id }
}

struct PlacesMapView: View {
    @Environment(\.lvPalette) private var palette
    @State private var viewModel: PlacesViewModel
    @State private var selection: MemoryPin?

    init(client: any MemoryClientProtocol) {
        _viewModel = State(initialValue: PlacesViewModel(client: client))
    }

    var body: some View {
        content
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .sheet(item: $selection) { pin in
                PlaceDetailSheet(pin: pin)
                    .presentationDetents([.medium])
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .lvBackground()
        case let .failed(message):
            failure(message)
        case .loaded:
            if viewModel.pins.isEmpty {
                empty
            } else {
                map
            }
        }
    }

    private var map: some View {
        Map(initialPosition: viewModel.boundingRegion.map { .region($0) } ?? .automatic) {
            ForEach(viewModel.pins) { pin in
                Annotation(pin.placeName ?? pin.shortTitle, coordinate: pin.coordinate) {
                    Button { selection = pin } label: {
                        LVIconView(.location, size: 18, tint: .white)
                            .padding(8)
                            .background(Circle().fill(palette.primary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Memory at \(pin.placeName ?? pin.shortTitle)")
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var empty: some View {
        LVEmptyState(
            mascot: .thinking,
            headline: "No places yet.",
            supporting: "Turn on location for a capture and it will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            LVIconView(.exclamationmarkTriangleFill, size: 42, tint: palette.accent)
            Text("Couldn't load your places")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
                .tint(palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }
}

private struct PlaceDetailSheet: View {
    @Environment(\.lvPalette) private var palette
    let pin: MemoryPin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoryMapCard(
                    lat: pin.coordinate.latitude,
                    lng: pin.coordinate.longitude,
                    placeName: pin.placeName,
                    height: 160
                )
                if let createdAt = pin.createdAt {
                    HStack(spacing: 8) {
                        LVIconView(.clock, size: 13, tint: palette.textSecondary)
                        Text(createdAt, style: .date)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                }
                Text(pin.title)
                    .font(LVTypography.body.font)
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .lvBackground()
    }
}
