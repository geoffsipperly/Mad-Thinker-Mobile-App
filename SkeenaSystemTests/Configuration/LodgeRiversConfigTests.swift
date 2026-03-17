import XCTest
@testable import SkeenaSystem

/// Tests for the LODGE_RIVERS configuration property in AppEnvironment.
/// Verifies comma-separated parsing, override support, and API compatibility.
@MainActor
final class LodgeRiversConfigTests: XCTestCase {

  override func setUp() {
    super.setUp()
    AppEnvironment.shared.overrideLodgeRivers = nil
  }

  override func tearDown() {
    AppEnvironment.shared.overrideLodgeRivers = nil
    super.tearDown()
  }

  // MARK: - Default Value

  func testLodgeRivers_defaultsToFiveRivers() {
    let rivers = AppEnvironment.shared.lodgeRivers
    XCTAssertEqual(rivers.count, 5, "Default should have 5 rivers")
    XCTAssertEqual(rivers, [
      "Nehalem River", "Wilson River", "Trask River", "Nestucca River", "Kilchis River"
    ])
  }

  func testLodgeRivers_neverEmpty() {
    let rivers = AppEnvironment.shared.lodgeRivers
    XCTAssertFalse(rivers.isEmpty, "Lodge rivers should never be empty")
  }

  // MARK: - Override

  func testLodgeRivers_respectsOverride() {
    AppEnvironment.shared.overrideLodgeRivers = ["Test River", "Demo Creek"]
    XCTAssertEqual(AppEnvironment.shared.lodgeRivers, ["Test River", "Demo Creek"])
  }

  func testLodgeRivers_clearingOverrideRestoresDefault() {
    AppEnvironment.shared.overrideLodgeRivers = ["Test River"]
    XCTAssertEqual(AppEnvironment.shared.lodgeRivers.count, 1)

    AppEnvironment.shared.overrideLodgeRivers = nil
    XCTAssertEqual(AppEnvironment.shared.lodgeRivers.count, 5,
                   "Clearing override should restore default value")
  }

  func testLodgeRivers_emptyOverrideReturnsEmpty() {
    AppEnvironment.shared.overrideLodgeRivers = []
    XCTAssertEqual(AppEnvironment.shared.lodgeRivers, [],
                   "Empty override should return empty array")
  }

  // MARK: - API Compatibility

  func testLodgeRivers_riverNamesAreAPICompatible() {
    // River names from config are sent directly to the API,
    // so they must match the expected API format
    let rivers = AppEnvironment.shared.lodgeRivers
    for river in rivers {
      XCTAssertFalse(river.isEmpty, "River name should not be empty")
      XCTAssertEqual(river, river.trimmingCharacters(in: .whitespaces),
                     "River name '\(river)' should have no leading/trailing whitespace")
    }
  }
}
