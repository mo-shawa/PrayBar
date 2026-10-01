import CoreLocation
import Foundation
import PrayBarCore

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var state: LocationRequestState
    var onChange: ((Bool) -> Void)?
    private var manager: CLLocationManager?
    private var timeout: Timer?
    private var requestedFix = false

    init(cache: LocationFix?) { state = LocationRequestState(cache: cache); super.init() }

    func refresh() {
        guard let id = state.begin() else { return }
        onChange?(false)
        guard CLLocationManager.locationServicesEnabled() else {
            finish(id: id, failure: "Location Services are disabled.")
            return
        }
        // A fresh manager gives obsolete delegate callbacks an identity we can reject.
        let manager = CLLocationManager()
        self.manager = manager
        requestedFix = false
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        let timer = Timer(timeInterval: LocationRequestState.timeout, repeats: false) { [weak self] _ in
            self?.finish(id: id, failure: "Location lookup timed out.")
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        timeout = timer
        handleAuthorization(manager)
    }

    func cancel() {
        state.cancel()
        stop()
    }

    private func stop() {
        timeout?.invalidate(); timeout = nil
        manager?.delegate = nil
        manager?.stopUpdatingLocation() // Also cancels requestLocation on macOS.
        manager = nil
        requestedFix = false
    }

    private func handleAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager, let id = state.activeID else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            if !requestedFix { requestedFix = true; manager.requestLocation() }
        case .denied: finish(id: id, failure: "Location permission denied.")
        case .restricted: finish(id: id, failure: "Location permission restricted.")
        @unknown default: finish(id: id, failure: "Location authorization unavailable.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { handleAuthorization(manager) }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let id = state.activeID else { return }
        let now = Date()
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 5_000 &&
            (-60...300).contains(now.timeIntervalSince($0.timestamp)) &&
            CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            finish(id: id, failure: "No sufficiently recent location fix is available.")
            return
        }
        let fix = LocationFix(point: GeoPoint(latitude: location.coordinate.latitude,
                                              longitude: location.coordinate.longitude), acquiredAt: location.timestamp)
        finish(id: id, fix: fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager, let id = state.activeID else { return }
        let denied = (error as? CLError)?.code == .denied
        finish(id: id, failure: denied ? "Location permission denied." : "Location lookup failed.")
    }

    private func finish(id: UInt64, fix: LocationFix? = nil, failure: String? = nil) {
        guard state.finish(id: id, fix: fix, failure: failure) else { return }
        stop()
        onChange?(fix != nil)
    }

    deinit { timeout?.invalidate(); manager?.stopUpdatingLocation() }
}
