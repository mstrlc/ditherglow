import AppKit
import CoreLocation
import MapKit
import Observation

/// The opt-in "Current Location" mode: asks Core Location for a rough fix and saves it to `Preferences`,
/// where `Sun.location()` reads it. Only runs while that mode is chosen, so nobody is asked for access otherwise.
@Observable
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// The last fix failed (e.g. Wi-Fi off); the saved one, if any, stays in use.
    private(set) var failed = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var mode = Preferences.defaultLocationMode
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        manager.delegate = self
        // The sun moves about a minute per 15 km of longitude: city-level accuracy is plenty, and quicker.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        authorization = manager.authorizationStatus
        mode = currentMode
        refresh()
        // Saving a fix also posts this, so only act when the mode itself changes.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentMode != self.mode else { return }
                self.mode = self.currentMode
                self.refresh()
            }
        })
        // A laptop may have moved while asleep.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// Asks for access the first time, then for one fix. Does nothing outside `.current` mode.
    func refresh() {
        guard mode == .current else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    private var currentMode: Preferences.LocationMode {
        UserDefaults.standard.string(forKey: Preferences.locationModeKey).flatMap(Preferences.LocationMode.init)
            ?? Preferences.defaultLocationMode
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            refresh()
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            failed = false
            save(location)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        MainActor.assumeIsolated { failed = true }
    }

    private func save(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: Preferences.currentLatitudeKey)
        defaults.set(location.coordinate.longitude, forKey: Preferences.currentLongitudeKey)
        Task {
            // Keep the old name if the lookup fails (e.g. offline): it's only a label.
            if let name = await placeName(location) {
                defaults.set(name, forKey: Preferences.currentPlaceKey)
            }
        }
    }

    private func placeName(_ location: CLLocation) async -> String? {
        if #available(macOS 26, *) {
            let items = try? await MKReverseGeocodingRequest(location: location)?.mapItems
            return items?.first?.addressRepresentations?.cityName
        } else {
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks?.first?.locality
        }
    }
}
