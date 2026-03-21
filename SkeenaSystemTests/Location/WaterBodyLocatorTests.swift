import XCTest
import CoreLocation
@testable import SkeenaSystem

/// Tests for WaterBodyLocator and its ray-casting point-in-polygon algorithm
/// with boundary tolerance.
@MainActor
final class WaterBodyLocatorTests: XCTestCase {

  // MARK: - Test Data

  // Interior of Puget Sound (Seattle waterfront area)
  private let seattleWaterfront = CLLocationCoordinate2D(latitude: 47.610, longitude: -122.370)

  // Interior of Puget Sound (Tacoma / Commencement Bay)
  private let tacomaCommencement = CLLocationCoordinate2D(latitude: 47.290, longitude: -122.440)

  // Interior of Hood Canal (mid-canal)
  private let hoodCanalMid = CLLocationCoordinate2D(latitude: 47.630, longitude: -122.830)

  // Point Wilson — exactly on the first vertex of the Puget Sound polygon
  private let pointWilson = CLLocationCoordinate2D(latitude: 48.170, longitude: -122.760)

  // A location clearly outside all water bodies (Spokane, WA)
  private let spokaneCoord = CLLocationCoordinate2D(latitude: 47.658, longitude: -117.426)

  // A location inland near Seattle (Bellevue)
  private let bellevueCoord = CLLocationCoordinate2D(latitude: 47.610, longitude: -122.200)

  // MARK: - Simple triangle for unit-level polygon tests

  private let triangle: [CLLocationCoordinate2D] = [
    CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
    CLLocationCoordinate2D(latitude: 0.0, longitude: 10.0),
    CLLocationCoordinate2D(latitude: 10.0, longitude: 5.0),
  ]

  // MARK: - pointInPolygon: Basic Tests

  func testPointInPolygon_insideTriangle_returnsTrue() {
    let point = CLLocationCoordinate2D(latitude: 3.0, longitude: 5.0)
    XCTAssertTrue(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                  "Point clearly inside triangle should return true")
  }

  func testPointInPolygon_outsideTriangle_returnsFalse() {
    let point = CLLocationCoordinate2D(latitude: 11.0, longitude: 5.0)
    XCTAssertFalse(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                   "Point clearly outside triangle should return false")
  }

  func testPointInPolygon_emptyPolygon_returnsFalse() {
    let point = CLLocationCoordinate2D(latitude: 5.0, longitude: 5.0)
    XCTAssertFalse(WaterBodyLocator.pointInPolygon(point: point, polygon: []),
                   "Empty polygon should return false")
  }

  func testPointInPolygon_twoVertices_returnsFalse() {
    let point = CLLocationCoordinate2D(latitude: 0.0, longitude: 5.0)
    let line = [
      CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
      CLLocationCoordinate2D(latitude: 0.0, longitude: 10.0),
    ]
    XCTAssertFalse(WaterBodyLocator.pointInPolygon(point: point, polygon: line),
                   "Degenerate polygon with only 2 vertices should return false")
  }

  // MARK: - pointInPolygon: Boundary Tolerance Tests

  func testPointInPolygon_onVertex_returnsTrue() {
    // Exactly on the first vertex of the triangle
    let point = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    XCTAssertTrue(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                  "Point exactly on a vertex should return true (boundary tolerance)")
  }

  func testPointInPolygon_onEdge_returnsTrue() {
    // Midpoint of the bottom edge (0,0)→(0,10) at (0, 5)
    let point = CLLocationCoordinate2D(latitude: 0.0, longitude: 5.0)
    XCTAssertTrue(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                  "Point exactly on an edge should return true (boundary tolerance)")
  }

  func testPointInPolygon_justOutsideEdge_withinEpsilon_returnsTrue() {
    // Slightly outside the bottom edge, within epsilon (~11m)
    let point = CLLocationCoordinate2D(latitude: -0.00005, longitude: 5.0)
    XCTAssertTrue(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                  "Point just outside edge but within epsilon should return true")
  }

  func testPointInPolygon_wellOutsideEdge_returnsFalse() {
    // Clearly outside the bottom edge
    let point = CLLocationCoordinate2D(latitude: -1.0, longitude: 5.0)
    XCTAssertFalse(WaterBodyLocator.pointInPolygon(point: point, polygon: triangle),
                   "Point well outside edge should return false")
  }

  // MARK: - WaterBodyLocator: Puget Sound Detection

  func testWaterBodyName_seattleWaterfront_returnsPugetSound() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: seattleWaterfront.latitude,
                              longitude: seattleWaterfront.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertEqual(result, "Puget Sound",
                   "Seattle waterfront should be detected as Puget Sound")
  }

  func testWaterBodyName_tacomaCommencement_returnsPugetSound() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: tacomaCommencement.latitude,
                              longitude: tacomaCommencement.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertEqual(result, "Puget Sound",
                   "Tacoma Commencement Bay should be detected as Puget Sound")
  }

  func testWaterBodyName_pointWilsonVertex_returnsPugetSound() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: pointWilson.latitude,
                              longitude: pointWilson.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertEqual(result, "Puget Sound",
                   "Point Wilson (polygon vertex) should be detected as Puget Sound via boundary tolerance")
  }

  // MARK: - WaterBodyLocator: Hood Canal Detection

  func testWaterBodyName_hoodCanalMid_returnsHoodCanal() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: hoodCanalMid.latitude,
                              longitude: hoodCanalMid.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertEqual(result, "Hood Canal",
                   "Mid Hood Canal should be detected as Hood Canal (checked before Puget Sound)")
  }

  // MARK: - WaterBodyLocator: Negative Cases

  func testWaterBodyName_spokane_returnsNil() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: spokaneCoord.latitude,
                              longitude: spokaneCoord.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertNil(result,
                 "Spokane should not match any water body")
  }

  func testWaterBodyName_bellevue_returnsNil() {
    let locator = WaterBodyLocator.shared
    let location = CLLocation(latitude: bellevueCoord.latitude,
                              longitude: bellevueCoord.longitude)

    let result = locator.waterBodyName(at: location)
    XCTAssertNil(result,
                 "Bellevue (inland) should not match any water body")
  }

  func testWaterBodyName_nilLocation_returnsNil() {
    let locator = WaterBodyLocator.shared
    let result = locator.waterBodyName(at: nil)
    XCTAssertNil(result,
                 "Nil location should return nil")
  }

  // MARK: - WaterBodyLocator: Configuration

  func testHasWaterBodies_returnsTrue() {
    let locator = WaterBodyLocator.shared
    XCTAssertTrue(locator.hasWaterBodies,
                  "Should have water bodies configured")
  }

  // MARK: - WaterBodyAtlas: Check Order

  func testCheckOrder_hoodCanalBeforePugetSound() {
    let order = WaterBodyAtlas.checkOrder
    guard let hoodIndex = order.firstIndex(of: "Hood Canal"),
          let pugetIndex = order.firstIndex(of: "Puget Sound") else {
      XCTFail("Both Hood Canal and Puget Sound should be in checkOrder")
      return
    }
    XCTAssertLessThan(hoodIndex, pugetIndex,
                      "Hood Canal should be checked before Puget Sound (more specific first)")
  }

  // MARK: - Performance

  func testPointInPolygon_performance() {
    let pugetSound = WaterBodyAtlas.all["Puget Sound"]!
    let point = CLLocationCoordinate2D(latitude: 47.610, longitude: -122.370)

    measure {
      for _ in 0..<10_000 {
        _ = WaterBodyLocator.pointInPolygon(point: point, polygon: pugetSound)
      }
    }
  }
}
