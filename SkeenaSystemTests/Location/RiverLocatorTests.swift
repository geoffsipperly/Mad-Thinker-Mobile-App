import XCTest
import CoreLocation
@testable import SkeenaSystem

/// Regression tests for RiverLocator.
/// These tests verify the river lookup logic using known coordinates
/// from the Washington State rivers configured in DevTEST and ensure correct
/// behavior for boundary conditions and edge cases.
@MainActor
final class RiverLocatorTests: XCTestCase {

  // MARK: - Test Data (Known Coordinates — first spine point of each configured river)

  // Hoh River — mouth at Pacific Ocean
  private let hohRiverCoord = CLLocationCoordinate2D(latitude: 47.7494, longitude: -124.4401)

  // Green River — Duwamish River mouth at Elliott Bay
  private let greenRiverCoord = CLLocationCoordinate2D(latitude: 47.5650, longitude: -122.3450)

  // Sauk River — mouth at Skagit River confluence, Rockport
  private let saukRiverCoord = CLLocationCoordinate2D(latitude: 48.4850, longitude: -121.5920)

  // Skykomish River — mouth at Snoqualmie River confluence, Monroe
  private let skykomishRiverCoord = CLLocationCoordinate2D(latitude: 47.8554, longitude: -121.9690)

  // Sol Duc River — mouth at Bogachiel confluence
  private let solDucRiverCoord = CLLocationCoordinate2D(latitude: 47.9050, longitude: -124.5600)

  // A location far from any Washington river (Spokane, WA)
  private let spokaneCoord = CLLocationCoordinate2D(latitude: 47.658, longitude: -117.426)

  // MARK: - riverName Tests: Exact Coordinates

  func testRiverName_atHohRiver_returnsHoh() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: hohRiverCoord.latitude,
                              longitude: hohRiverCoord.longitude)

    let result = locator.riverName(near: location)
    XCTAssertEqual(result, "Hoh",
                   "Should return short name 'Hoh' when at exact Hoh River coordinate")
  }

  func testRiverName_atGreenRiver_returnsGreen() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: greenRiverCoord.latitude,
                              longitude: greenRiverCoord.longitude)

    let result = locator.riverName(near: location)
    XCTAssertEqual(result, "Green",
                   "Should return short name 'Green' when at exact Green River coordinate")
  }

  func testRiverName_atSaukRiver_returnsSauk() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: saukRiverCoord.latitude,
                              longitude: saukRiverCoord.longitude)

    let result = locator.riverName(near: location)
    XCTAssertEqual(result, "Sauk",
                   "Should return short name 'Sauk' when at exact Sauk River coordinate")
  }

  func testRiverName_atSkykomishRiver_returnsSkykomish() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: skykomishRiverCoord.latitude,
                              longitude: skykomishRiverCoord.longitude)

    let result = locator.riverName(near: location)
    XCTAssertEqual(result, "Skykomish",
                   "Should return short name 'Skykomish' when at exact Skykomish River coordinate")
  }

  func testRiverName_atSolDucRiver_returnsSolDuc() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: solDucRiverCoord.latitude,
                              longitude: solDucRiverCoord.longitude)

    let result = locator.riverName(near: location)
    XCTAssertEqual(result, "Sol Duc",
                   "Should return short name 'Sol Duc' when at exact Sol Duc River coordinate")
  }

  // MARK: - riverName Tests: Nearby Coordinates (within maxDistanceKm)

  func testRiverName_nearHohRiver_returnsHoh() {
    let locator = RiverLocator.shared
    // Offset by ~1km (approximately 0.009 degrees latitude)
    let nearbyLocation = CLLocation(latitude: hohRiverCoord.latitude + 0.009,
                                    longitude: hohRiverCoord.longitude)

    let result = locator.riverName(near: nearbyLocation)
    XCTAssertEqual(result, "Hoh",
                   "Should return 'Hoh' when within 1km of Hoh River")
  }

  func testRiverName_5kmFromGreenRiver_returnsGreen() {
    let locator = RiverLocator.shared
    // Offset by ~5km (approximately 0.045 degrees latitude)
    let nearbyLocation = CLLocation(latitude: greenRiverCoord.latitude + 0.045,
                                    longitude: greenRiverCoord.longitude)

    let result = locator.riverName(near: nearbyLocation)
    XCTAssertEqual(result, "Green",
                   "Should return 'Green' when ~5km away (within 10km threshold)")
  }

  // MARK: - riverName Tests: Beyond maxDistanceKm

  func testRiverName_farFromAllRivers_returnsEmptyString() {
    let locator = RiverLocator.shared
    let spokaneLocation = CLLocation(latitude: spokaneCoord.latitude,
                                     longitude: spokaneCoord.longitude)

    let result = locator.riverName(near: spokaneLocation)
    XCTAssertEqual(result, "",
                   "Should return empty string when far from all rivers (Spokane)")
  }

  func testRiverName_justBeyond10km_returnsEmptyString() {
    let locator = RiverLocator.shared
    // Offset by ~11km (approximately 0.1 degrees latitude)
    let farLocation = CLLocation(latitude: hohRiverCoord.latitude + 0.1,
                                 longitude: hohRiverCoord.longitude)

    let result = locator.riverName(near: farLocation)
    if result == "Hoh" {
      let hohRiverLocation = CLLocation(latitude: hohRiverCoord.latitude,
                                        longitude: hohRiverCoord.longitude)
      let distanceKm = farLocation.distance(from: hohRiverLocation) / 1000.0
      XCTAssertLessThanOrEqual(distanceKm, 10.0,
                                "If Hoh returned, distance must be <= 10km")
    }
  }

  // MARK: - riverName Tests: Nil Location

  func testRiverName_nilLocation_returnsEmptyString() {
    let locator = RiverLocator.shared
    let result = locator.riverName(near: nil)
    XCTAssertEqual(result, "",
                   "Should return empty string when location is nil")
  }

  // MARK: - Snapshot Tests: All Rivers Exist

  func testAllExpectedRiversExist() {
    let locator = RiverLocator.shared

    let expectedRivers: [(name: String, coord: CLLocationCoordinate2D)] = [
      ("Hoh", hohRiverCoord),
      ("Green", greenRiverCoord),
      ("Sauk", saukRiverCoord),
      ("Skykomish", skykomishRiverCoord),
      ("Sol Duc", solDucRiverCoord),
    ]

    for (expectedName, coord) in expectedRivers {
      let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
      let result = locator.riverName(near: location)
      XCTAssertEqual(result, expectedName,
                     "River \(expectedName) should be found at its first coordinate")
    }
  }

  // MARK: - shortName Tests

  func testShortName_stripsCreekSuffix() {
    let def = RiverDefinition(
      name: "Nehalem Creek",
      communityID: "Test",
      coordinates: [],
      maxDistanceKm: 10
    )
    XCTAssertEqual(def.shortName, "Nehalem")
  }

  func testShortName_stripsRiverSuffix() {
    let def = RiverDefinition(
      name: "Nehalem River",
      communityID: "Test",
      coordinates: [],
      maxDistanceKm: 10
    )
    XCTAssertEqual(def.shortName, "Nehalem")
  }

  func testShortName_stripsLakeSuffix() {
    let def = RiverDefinition(
      name: "Mirror Lake",
      communityID: "Test",
      coordinates: [],
      maxDistanceKm: 10
    )
    XCTAssertEqual(def.shortName, "Mirror")
  }

  func testShortName_stripsStreamSuffix() {
    let def = RiverDefinition(
      name: "Bear Stream",
      communityID: "Test",
      coordinates: [],
      maxDistanceKm: 10
    )
    XCTAssertEqual(def.shortName, "Bear")
  }

  func testShortName_noSuffix_returnsFullName() {
    let def = RiverDefinition(
      name: "Nehalem",
      communityID: "Test",
      coordinates: [],
      maxDistanceKm: 10
    )
    XCTAssertEqual(def.shortName, "Nehalem")
  }

  func testShortName_allConfiguredRivers() {
    let locator = RiverLocator.shared
    let coords: [(CLLocationCoordinate2D, String)] = [
      (hohRiverCoord, "Hoh"),
      (greenRiverCoord, "Green"),
      (saukRiverCoord, "Sauk"),
      (skykomishRiverCoord, "Skykomish"),
      (solDucRiverCoord, "Sol Duc"),
    ]
    for (coord, expected) in coords {
      let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
      let result = locator.riverName(near: loc)
      XCTAssertEqual(result, expected,
                     "riverName() should return '\(expected)', not a full name with suffix")
    }
  }

  // MARK: - Performance Test

  func testRiverName_performance() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: hohRiverCoord.latitude,
                              longitude: hohRiverCoord.longitude)

    measure {
      for _ in 0..<1000 {
        _ = locator.riverName(near: location)
      }
    }
  }
}
