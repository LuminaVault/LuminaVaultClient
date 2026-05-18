// LuminaVaultClient/LuminaVaultClient/Services/Location/LocationService.swift
//
// HER-34 — one-shot CoreLocation wrapper. The capture UI flips a per-
// capture "tag with location" toggle; flipping it on triggers
// `requestFix()` which returns (lat, lng, accuracyM, placeName?) or nil
// on denial/timeout. All four fields stay nil for captures where the
// user kept the toggle off.
//
// CoreLocation types are not `Sendable`. `CLLocationManager` is pinned
// to `@MainActor` so the delegate callbacks and manager state stay on
// the main actor; `requestFix()` is non-isolated and bridges into the
// MainActor via an `await` hop. `CLGeocoder` is invoked off-actor with
// the produced `CLLocation` because the geocode call is async and
// doesn't need MainActor.

@preconcurrency import CoreLocation
import Foundation
import OSLog

private nonisolated(unsafe) let log = Logger(subsystem: "com.luminavault", category: "location")

protocol LocationServiceProtocol: Sendable {
    func requestFix() async -> LocationFix?
}

struct LocationFix: Sendable, Equatable {
    let lat: Double
    let lng: Double
    let accuracyM: Double
    let placeName: String?
}

final class LocationService: LocationServiceProtocol, @unchecked Sendable {
    func requestFix() async -> LocationFix? {
        let location = await Self.fetchLocation()
        guard let location else { return nil }

        let placeName = await Self.reverseGeocode(location: location)
        return LocationFix(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            placeName: placeName,
        )
    }

    @MainActor
    private static func fetchLocation() async -> CLLocation? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            let bridge = Delegate(continuation: cont)
            // Bridge retains the manager + itself until CL fires. Held
            // strongly inside the continuation closure scope so neither
            // dies before the delegate callback lands.
            bridge.start()
        }
    }

    private static func reverseGeocode(location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.formattedPlaceName
        } catch {
            log.debug("reverse geocode failed: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        private var continuation: CheckedContinuation<CLLocation?, Never>?
        private let manager = CLLocationManager()
        private var selfRef: Delegate?

        init(continuation: CheckedContinuation<CLLocation?, Never>) {
            self.continuation = continuation
            super.init()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        func start() {
            // Retain self so the manager + delegate survive until the
            // CL callback fires. Released inside `resume`.
            selfRef = self

            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                resume(nil)
                return
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            @unknown default:
                resume(nil)
                return
            }
        }

        private func resume(_ value: CLLocation?) {
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(returning: value)
            selfRef = nil
        }

        func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            resume(locations.first)
        }

        func locationManager(_: CLLocationManager, didFailWithError error: Error) {
            log.debug("CL didFailWithError: \(error.localizedDescription)")
            resume(nil)
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .denied, .restricted:
                resume(nil)
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                break
            }
        }
    }
}

private extension CLPlacemark {
    nonisolated var formattedPlaceName: String? {
        let parts = [name, locality, administrativeArea, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
