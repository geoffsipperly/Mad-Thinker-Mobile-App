import XCTest
@testable import SkeenaSystem

/// Tests for the entitlement system.
///
/// Validates:
/// 1. readEntitlement correctly reads Bool values from Info.plist
/// 2. readEntitlement returns false for absent or empty keys
/// 3. Consecutive reads return consistent values
/// 4. Non-boolean Info.plist keys are not misinterpreted as true
final class FeatureFlagTests: XCTestCase {

  // MARK: - readEntitlement helper behaviour

  func testReadFeatureFlag_returnsFalseForAbsentKey() {
    // A key that is not in Info.plist should default to false
    let result = readEntitlement("E_NONEXISTENT_FLAG_12345")
    XCTAssertFalse(result, "readEntitlement should return false for keys not present in Info.plist")
  }

  func testReadFeatureFlag_returnsFalseForEmptyKey() {
    let result = readEntitlement("")
    XCTAssertFalse(result, "readEntitlement should return false for an empty key string")
  }

  // MARK: - Consistency: consecutive reads return the same value

  func testReadFeatureFlag_isConsistentAcrossReads() {
    // Pick a flag that exists in Info.plist and verify two reads agree
    let flagsToCheck = [
      "E_FLIGHT_INFO",
      "E_MEET_STAFF",
      "E_GEAR_CHECKLIST",
      "E_MANAGE_LICENSES",
      "E_SELF_ASSESSMENT",
      "E_CATCH_CAROUSEL",
      "E_CATCH_MAP",
    ]

    for flag in flagsToCheck {
      let first = readEntitlement(flag)
      let second = readEntitlement(flag)
      XCTAssertEqual(first, second,
                     "readEntitlement(\"\(flag)\") should return the same value on consecutive reads")
    }
  }

  // MARK: - Exhaustiveness: all expected flags exist in Info.plist

  func testAllFeatureFlags_presentInInfoPlist() {
    let expectedFlags = [
      "E_FLIGHT_INFO",
      "E_MEET_STAFF",
      "E_GEAR_CHECKLIST",
      "E_MANAGE_LICENSES",
      "E_SELF_ASSESSMENT",
      "E_CATCH_CAROUSEL",
      "E_CATCH_MAP",
    ]

    for flag in expectedFlags {
      let value = Bundle.main.object(forInfoDictionaryKey: flag)
      XCTAssertNotNil(value, "\(flag) should be present in Info.plist (check xcconfig and Info.plist entries)")
    }
  }

  // MARK: - Consistency: non-FF keys are not treated as entitlements

  func testNonFeatureFlag_keyReturnsExpectedValue() {
    // API_BASE_URL is a string config key, not a boolean flag.
    // readEntitlement should return false since it's not "true"/"YES"/1.
    let value = readEntitlement("API_BASE_URL")
    XCTAssertFalse(value, "Non-boolean Info.plist values should not be interpreted as true")
  }
}
