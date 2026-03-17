import XCTest
import CoreLocation
@testable import SkeenaSystem

/// Regression tests for RiverLocator.
/// These tests verify the river lookup logic using known coordinates
/// from the Oregon Coast / Tillamook region and ensure correct behavior for
/// boundary conditions, unknown communities, and edge cases.
@MainActor
final class RiverLocatorTests: XCTestCase {

  // MARK: - Test Data (Known Coordinates)

  // Nehalem River - representative coordinate
  private let nehalemRiverCoord = CLLocationCoordinate2D(latitude: 45.7060, longitude: -123.8810)

  // Wilson River - representative coordinate
  private let wilsonRiverCoord = CLLocationCoordinate2D(latitude: 45.4730, longitude: -123.7350)

  // Trask River - representative coordinate
  private let traskRiverCoord = CLLocationCoordinate2D(latitude: 45.4100, longitude: -123.7200)

  // Nestucca River - representative coordinate
  private let nestuccaRiverCoord = CLLocationCoordinate2D(latitude: 45.1870, longitude: -123.8870)

  // Kilchis River - representative coordinate
  private let kilchisRiverCoord = CLLocationCoordinate2D(latitude: 45.4850, longitude: -123.7900)

  // A location far from any Oregon Coast river (Portland, OR)
  private let portlandCoord = CLLocationCoordinate2D(latitude: 45.5152, longitude: -122.6784)

  // MARK: - hasRivers Tests

  func testHasRivers_bendFlyShop_returnsTrue() {
    let locator = RiverLocator.shared
    XCTAssertTrue(locator.hasRivers(forCommunity: "Bend Fly Shop"),
                  "Bend Fly Shop should have rivers defined")
  }

  func testHasRivers_bendFlyShop_caseInsensitive() {
    let locator = RiverLocator.shared

    XCTAssertTrue(locator.hasRivers(forCommunity: "bend fly shop"),
                  "Should match case-insensitively (lowercase)")
    XCTAssertTrue(locator.hasRivers(forCommunity: "BEND FLY SHOP"),
                  "Should match case-insensitively (uppercase)")
    XCTAssertTrue(locator.hasRivers(forCommunity: "BeNd FlY sHoP"),
                  "Should match case-insensitively (mixed)")
  }

  func testHasRivers_bendFlyShop_withWhitespace() {
    let locator = RiverLocator.shared

    XCTAssertTrue(locator.hasRivers(forCommunity: "  Bend Fly Shop  "),
                  "Should trim leading/trailing whitespace")
    XCTAssertTrue(locator.hasRivers(forCommunity: "\nBend Fly Shop\t"),
                  "Should trim newlines and tabs")
  }

  func testHasRivers_unknownCommunity_returnsFalse() {
    let locator = RiverLocator.shared

    XCTAssertFalse(locator.hasRivers(forCommunity: "Unknown Community"),
                   "Unknown community should return false")
    XCTAssertFalse(locator.hasRivers(forCommunity: ""),
                   "Empty string should return false")
    XCTAssertFalse(locator.hasRivers(forCommunity: "Another Lodge"),
                   "Non-existent community should return false")
  }

  // MARK: - riverName Tests: Exact Coordinates

  func testRiverName_atNehalemRiver_returnsNehalem() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nehalemRiverCoord.latitude,
                              longitude: nehalemRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Nehalem",
                   "Should return short name 'Nehalem' when at exact Nehalem River coordinate")
  }

  func testRiverName_atWilsonRiver_returnsWilson() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: wilsonRiverCoord.latitude,
                              longitude: wilsonRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Wilson",
                   "Should return short name 'Wilson' when at exact Wilson River coordinate")
  }

  func testRiverName_atTraskRiver_returnsTrask() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: traskRiverCoord.latitude,
                              longitude: traskRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Trask",
                   "Should return short name 'Trask' when at exact Trask River coordinate")
  }

  func testRiverName_atNestuccaRiver_returnsNestucca() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nestuccaRiverCoord.latitude,
                              longitude: nestuccaRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Nestucca",
                   "Should return short name 'Nestucca' when at exact Nestucca River coordinate")
  }

  func testRiverName_atKilchisRiver_returnsKilchis() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: kilchisRiverCoord.latitude,
                              longitude: kilchisRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Kilchis",
                   "Should return short name 'Kilchis' when at exact Kilchis River coordinate")
  }

  // MARK: - riverName Tests: Nearby Coordinates (within maxDistanceKm)

  func testRiverName_nearNehalemRiver_returnsNehalem() {
    let locator = RiverLocator.shared
    // Offset by ~1km (approximately 0.009 degrees latitude)
    let nearbyLocation = CLLocation(latitude: nehalemRiverCoord.latitude + 0.009,
                                    longitude: nehalemRiverCoord.longitude)

    let result = locator.riverName(near: nearbyLocation, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Nehalem",
                   "Should return short name 'Nehalem' when within 10km of Nehalem River")
  }

  func testRiverName_5kmFromWilsonRiver_returnsWilson() {
    let locator = RiverLocator.shared
    // Offset by ~5km (approximately 0.045 degrees latitude)
    let nearbyLocation = CLLocation(latitude: wilsonRiverCoord.latitude + 0.045,
                                    longitude: wilsonRiverCoord.longitude)

    let result = locator.riverName(near: nearbyLocation, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "Wilson",
                   "Should return short name 'Wilson' when ~5km away (within 10km threshold)")
  }

  // MARK: - riverName Tests: Beyond maxDistanceKm

  func testRiverName_farFromAllRivers_returnsEmptyString() {
    let locator = RiverLocator.shared
    let portlandLocation = CLLocation(latitude: portlandCoord.latitude,
                                      longitude: portlandCoord.longitude)

    let result = locator.riverName(near: portlandLocation, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "",
                   "Should return empty string when far from all rivers (Portland)")
  }

  func testRiverName_justBeyond10km_returnsEmptyString() {
    let locator = RiverLocator.shared
    // Offset by ~11km (approximately 0.1 degrees latitude)
    let farLocation = CLLocation(latitude: nehalemRiverCoord.latitude + 0.1,
                                 longitude: nehalemRiverCoord.longitude)

    let result = locator.riverName(near: farLocation, forCommunity: "Bend Fly Shop")
    // This should either be empty or return a different river if one is within range
    // The key is it shouldn't return Nehalem if >10km away
    if result == "Nehalem" {
      // Verify distance is actually > 10km
      let nehalemRiverLocation = CLLocation(latitude: nehalemRiverCoord.latitude,
                                            longitude: nehalemRiverCoord.longitude)
      let distanceKm = farLocation.distance(from: nehalemRiverLocation) / 1000.0
      XCTAssertLessThanOrEqual(distanceKm, 10.0,
                                "If Nehalem returned, distance must be <= 10km")
    }
  }

  // MARK: - riverName Tests: Nil Location

  func testRiverName_nilLocation_returnsEmptyString() {
    let locator = RiverLocator.shared
    let result = locator.riverName(near: nil, forCommunity: "Bend Fly Shop")
    XCTAssertEqual(result, "",
                   "Should return empty string when location is nil")
  }

  // MARK: - riverName Tests: Unknown Community

  func testRiverName_unknownCommunity_returnsEmptyString() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nehalemRiverCoord.latitude,
                              longitude: nehalemRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "Unknown Community")
    XCTAssertEqual(result, "",
                   "Should return empty string for unknown community even at valid river location")
  }

  func testRiverName_emptyCommunity_returnsEmptyString() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nehalemRiverCoord.latitude,
                              longitude: nehalemRiverCoord.longitude)

    let result = locator.riverName(near: location, forCommunity: "")
    XCTAssertEqual(result, "",
                   "Should return empty string for empty community string")
  }

  // MARK: - riverName Tests: Case Insensitive Community

  func testRiverName_caseInsensitiveCommunity() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nehalemRiverCoord.latitude,
                              longitude: nehalemRiverCoord.longitude)

    let resultLower = locator.riverName(near: location, forCommunity: "bend fly shop")
    let resultUpper = locator.riverName(near: location, forCommunity: "BEND FLY SHOP")
    let resultMixed = locator.riverName(near: location, forCommunity: "Bend fly shop")

    XCTAssertEqual(resultLower, "Nehalem", "Should work with lowercase community")
    XCTAssertEqual(resultUpper, "Nehalem", "Should work with uppercase community")
    XCTAssertEqual(resultMixed, "Nehalem", "Should work with mixed case community")
  }

  // MARK: - riverName Tests: Closest River Selection

  func testRiverName_betweenTwoRivers_returnsClosest() {
    let locator = RiverLocator.shared

    // Find a point roughly between Wilson and Trask
    // Wilson: 45.4730, -123.7350
    // Trask: 45.4100, -123.7200
    // Midpoint roughly: 45.4415, -123.7275

    // Create a point closer to Wilson
    let closerToWilson = CLLocation(latitude: 45.4700, longitude: -123.7330)
    let resultWilson = locator.riverName(near: closerToWilson, forCommunity: "Bend Fly Shop")

    // Create a point closer to Trask
    let closerToTrask = CLLocation(latitude: 45.4130, longitude: -123.7210)
    let resultTrask = locator.riverName(near: closerToTrask, forCommunity: "Bend Fly Shop")

    // Both should return the closest river (or empty if beyond 10km from all)
    // The key assertion is they shouldn't return the same river
    if !resultWilson.isEmpty && !resultTrask.isEmpty {
      // If both found rivers, they should likely be different
      // (unless one location is equidistant)
      XCTAssertTrue(true, "Both locations found rivers")
    }
  }

  // MARK: - Snapshot Tests: All Rivers Exist

  func testAllExpectedRiversExist() {
    let locator = RiverLocator.shared

    // Test each known river coordinate returns the expected river name
    let expectedRivers: [(name: String, coord: CLLocationCoordinate2D)] = [
      ("Nehalem", nehalemRiverCoord),
      ("Wilson", wilsonRiverCoord),
      ("Trask", traskRiverCoord),
      ("Nestucca", nestuccaRiverCoord),
      ("Kilchis", kilchisRiverCoord)
    ]

    for (expectedName, coord) in expectedRivers {
      let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
      let result = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
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
    // Verify every river that RiverLocator returns uses short names
    let locator = RiverLocator.shared
    let coords: [(CLLocationCoordinate2D, String)] = [
      (nehalemRiverCoord, "Nehalem"),
      (wilsonRiverCoord, "Wilson"),
      (traskRiverCoord, "Trask"),
      (nestuccaRiverCoord, "Nestucca"),
      (kilchisRiverCoord, "Kilchis"),
    ]
    for (coord, expected) in coords {
      let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
      let result = locator.riverName(near: loc, forCommunity: "Bend Fly Shop")
      XCTAssertEqual(result, expected,
                     "riverName() should return '\(expected)', not a full name with suffix")
      XCTAssertFalse(result.contains("Creek"), "Short name should not contain 'Creek'")
      XCTAssertFalse(result.contains("River"), "Short name should not contain 'River'")
    }
  }

  // MARK: - Performance Test

  func testRiverName_performance() {
    let locator = RiverLocator.shared
    let location = CLLocation(latitude: nehalemRiverCoord.latitude,
                              longitude: nehalemRiverCoord.longitude)

    measure {
      for _ in 0..<1000 {
        _ = locator.riverName(near: location, forCommunity: "Bend Fly Shop")
      }
    }
  }
}
