// Bend Fly Shop

import Combine
import CoreLocation

final class LocationManager: NSObject, ObservableObject {
  private let manager = CLLocationManager()
  @Published var authorizationStatus: CLAuthorizationStatus
  @Published var lastLocation: CLLocation?

  override init() {
    authorizationStatus = manager.authorizationStatus
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
  }

  func request() { manager.requestWhenInUseAuthorization() }
  func start() { manager.startUpdatingLocation() }
  func stop() { manager.stopUpdatingLocation() }
}

extension LocationManager: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    AppLogging.log("[Location] Authorization changed: \(status.rawValue)", level: .info, category: .location)
    DispatchQueue.main.async { self.authorizationStatus = status }
    if status == .authorizedWhenInUse || status == .authorizedAlways { start() }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    lastLocation = locations.last
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    AppLogging.log("[Location] Error: \(error.localizedDescription)", level: .error, category: .location)
  }
}
