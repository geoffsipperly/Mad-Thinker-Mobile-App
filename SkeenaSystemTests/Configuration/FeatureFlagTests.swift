import XCTest
@testable import SkeenaSystem

/// Tests for the feature flag system.
///
/// Validates:
/// 1. readFeatureFlag correctly reads Bool values from Info.plist
/// 2. All new feature flags resolve to true in the DevTEST environment
/// 3. readFeatureFlag returns false for absent keys
/// 4. The FF_FLIGHT_INFO flag (existing) still works correctly
final class FeatureFlagTests: XCTestCase {

  // MARK: - readFeatureFlag helper behaviour

  func testReadFeatureFlag_returnsFalseForAbsentKey() {
    // A key that is not in Info.plist should default to false
    let result = readFeatureFlag("FF_NONEXISTENT_FLAG_12345")
    XCTAssertFalse(result, "readFeatureFlag should return false for keys not present in Info.plist")
  }

  func testReadFeatureFlag_returnsFalseForEmptyKey() {
    let result = readFeatureFlag("")
    XCTAssertFalse(result, "readFeatureFlag should return false for an empty key string")
  }

  // MARK: - AnglerTripPrepView feature flags (all default true in DevTEST)

  func testFlightInfoFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_FLIGHT_INFO")
    XCTAssertTrue(value, "FF_FLIGHT_INFO should be true in DevTEST xcconfig")
  }

  func testMeetStaffFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_MEET_STAFF")
    XCTAssertTrue(value, "FF_MEET_STAFF should be true in DevTEST xcconfig")
  }

  func testGearChecklistFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_GEAR_CHECKLIST")
    XCTAssertTrue(value, "FF_GEAR_CHECKLIST should be true in DevTEST xcconfig")
  }

  func testManageLicensesFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_MANAGE_LICENSES")
    XCTAssertTrue(value, "FF_MANAGE_LICENSES should be true in DevTEST xcconfig")
  }

  func testSelfAssessmentFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_SELF_ASSESSMENT")
    XCTAssertTrue(value, "FF_SELF_ASSESSMENT should be true in DevTEST xcconfig")
  }

  // MARK: - AnglerLandingView feature flags (all default true in DevTEST)

  func testCatchCarouselFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_CATCH_CAROUSEL")
    XCTAssertTrue(value, "FF_CATCH_CAROUSEL should be true in DevTEST xcconfig")
  }

  func testTheBuzzFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_THE_BUZZ")
    XCTAssertTrue(value, "FF_THE_BUZZ should be true in DevTEST xcconfig")
  }

  func testCatchMapFlag_isTrueInDevTEST() {
    let value = readFeatureFlag("FF_CATCH_MAP")
    XCTAssertTrue(value, "FF_CATCH_MAP should be true in DevTEST xcconfig")
  }

  // MARK: - Exhaustiveness: all expected flags exist in Info.plist

  func testAllFeatureFlags_presentInInfoPlist() {
    let expectedFlags = [
      "FF_FLIGHT_INFO",
      "FF_MEET_STAFF",
      "FF_GEAR_CHECKLIST",
      "FF_MANAGE_LICENSES",
      "FF_SELF_ASSESSMENT",
      "FF_CATCH_CAROUSEL",
      "FF_THE_BUZZ",
      "FF_CATCH_MAP",
    ]

    for flag in expectedFlags {
      let value = Bundle.main.object(forInfoDictionaryKey: flag)
      XCTAssertNotNil(value, "\(flag) should be present in Info.plist (check xcconfig and Info.plist entries)")
    }
  }

  // MARK: - Consistency: non-FF keys are not treated as feature flags

  func testNonFeatureFlag_keyReturnsExpectedValue() {
    // API_BASE_URL is a string config key, not a boolean flag.
    // readFeatureFlag should return false since it's not "true"/"YES"/1.
    let value = readFeatureFlag("API_BASE_URL")
    XCTAssertFalse(value, "Non-boolean Info.plist values should not be interpreted as true")
  }
}
