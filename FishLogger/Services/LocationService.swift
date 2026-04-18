import Foundation
import CoreLocation
import Observation

enum LocationError: Error, LocalizedError {
    case denied
    case restricted
    case unknown

    var errorDescription: String? {
        switch self {
        case .denied:     return "Location access denied. Enable it in Settings to tag catches with GPS."
        case .restricted: return "Location access is restricted on this device."
        case .unknown:    return "Couldn't determine your location. Try again in a moment."
        }
    }
}

@MainActor
@Observable
final class LocationService: NSObject {
    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestCurrentLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied:     throw LocationError.denied
        case .restricted: throw LocationError.restricted
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try await Task.sleep(nanoseconds: 200_000_000)
            if manager.authorizationStatus == .denied { throw LocationError.denied }
            if manager.authorizationStatus == .restricted { throw LocationError.restricted }
        default:
            break
        }

        if let existing = pendingContinuation {
            existing.resume(throwing: LocationError.unknown)
            pendingContinuation = nil
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            pendingContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            pendingContinuation?.resume(throwing: LocationError.unknown)
            pendingContinuation = nil
            return
        }
        pendingContinuation?.resume(returning: location)
        pendingContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
    }
}
