// LuminaVaultClient/LuminaVaultClient/Features/Places/MemoryMapCard.swift
//
// Renders the geo anchor a memory already carries.
//
// `MemoryDTO` has held `lat` / `lng` / `accuracyM` / `placeName` since HER-207,
// `LocationService` has been populating them from the capture toggle just as
// long — and until now **nothing in the app ever displayed any of it**. The
// data round-tripped to the server and back purely to be ignored. This is the
// smallest surface that makes it visible.
//
// MapKit is intentionally scoped to display. Location capture stays owned by
// `LocationService` (one-shot, when-in-use); nothing here requests a fix or
// tracks the user.

import LuminaVaultShared
import MapKit
import SwiftUI

/// A compact, non-interactive map showing where a memory was captured.
/// Renders nothing when the memory has no coordinate, so call sites can embed
/// it unconditionally.
struct MemoryMapCard: View {
    @Environment(\.lvPalette) private var palette

    let lat: Double?
    let lng: Double?
    let accuracyM: Double?
    let placeName: String?
    /// Height of the map itself. The caption sits below it.
    var height: CGFloat = 150

    init(
        lat: Double?,
        lng: Double?,
        accuracyM: Double? = nil,
        placeName: String? = nil,
        height: CGFloat = 150
    ) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.placeName = placeName
        self.height = height
    }

    init(memory: MemoryDTO, height: CGFloat = 150) {
        self.init(
            lat: memory.lat,
            lng: memory.lng,
            accuracyM: memory.accuracyM,
            placeName: memory.placeName,
            height: height
        )
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng, CLLocationCoordinate2DIsValid(.init(latitude: lat, longitude: lng))
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        if let coordinate {
            VStack(alignment: .leading, spacing: 8) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    // Widen the span with the fix's accuracy so a coarse fix
                    // doesn't imply more precision than it has.
                    latitudinalMeters: span(for: accuracyM),
                    longitudinalMeters: span(for: accuracyM)
                ))) {
                    Marker(placeName ?? "Captured here", coordinate: coordinate)
                        .tint(palette.primary)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(accessibilityDescription)

                HStack(spacing: 6) {
                    LVIconView(.location, size: 12, tint: palette.textSecondary)
                    Text(caption)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    /// Minimum 250m so a pinpoint fix still renders with usable context.
    private func span(for accuracy: Double?) -> Double {
        max(250, (accuracy ?? 0) * 6)
    }

    private var caption: String {
        if let placeName, !placeName.isEmpty { return placeName }
        guard let lat, let lng else { return "Captured location" }
        return String(format: "%.4f, %.4f", lat, lng)
    }

    private var accessibilityDescription: String {
        if let placeName, !placeName.isEmpty { return "Map. Captured at \(placeName)" }
        return "Map. Captured at \(caption)"
    }
}
