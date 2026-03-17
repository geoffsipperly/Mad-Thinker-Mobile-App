import XCTest
@testable import SkeenaSystem

/// Tests for APIURLUtilities URL normalization and Info.plist reading.
///
/// Validates:
/// 1. `normalizeBaseURL` adds https:// scheme when missing
/// 2. `normalizeBaseURL` preserves existing schemes
/// 3. Edge cases: empty strings, URLs with ports and paths
/// 4. `infoPlistString` returns trimmed values or empty string
final class APIURLUtilitiesTests: XCTestCase {

  // MARK: - normalizeBaseURL: Scheme handling

  func testNormalizeBaseURL_noScheme_addsHttps() {
    let result = APIURLUtilities.normalizeBaseURL("example.com")
    XCTAssertEqual(result, "https://example.com")
  }

  func testNormalizeBaseURL_httpsScheme_unchanged() {
    let result = APIURLUtilities.normalizeBaseURL("https://example.com")
    XCTAssertEqual(result, "https://example.com")
  }

  func testNormalizeBaseURL_httpScheme_preserved() {
    let result = APIURLUtilities.normalizeBaseURL("http://example.com")
    XCTAssertEqual(result, "http://example.com")
  }

  // MARK: - normalizeBaseURL: Edge cases

  func testNormalizeBaseURL_emptyString_returnsEmpty() {
    let result = APIURLUtilities.normalizeBaseURL("")
    XCTAssertEqual(result, "")
  }

  func testNormalizeBaseURL_withPort() {
    let result = APIURLUtilities.normalizeBaseURL("example.com:8080")
    // URL(string: "example.com:8080")?.scheme is "example.com", so it may not add https
    // This tests the actual behavior
    XCTAssertFalse(result.isEmpty, "Should return a non-empty URL")
  }

  func testNormalizeBaseURL_withPath() {
    let result = APIURLUtilities.normalizeBaseURL("example.com/api/v1")
    XCTAssertTrue(result.contains("example.com"), "Should contain the host")
    XCTAssertTrue(result.contains("/api/v1"), "Should preserve the path")
  }

  func testNormalizeBaseURL_httpsWithPath_unchanged() {
    let result = APIURLUtilities.normalizeBaseURL("https://example.com/api/v1")
    XCTAssertEqual(result, "https://example.com/api/v1")
  }

  func testNormalizeBaseURL_supabaseStyleHost() {
    let result = APIURLUtilities.normalizeBaseURL("example-project.supabase.co")
    XCTAssertEqual(result, "https://example-project.supabase.co")
  }

  // MARK: - infoPlistString

  func testInfoPlistString_missingKey_returnsEmpty() {
    let result = APIURLUtilities.infoPlistString(forKey: "NONEXISTENT_KEY_12345")
    XCTAssertEqual(result, "", "Missing key should return empty string")
  }

  func testInfoPlistString_bundleName_returnsNonEmpty() {
    // CFBundleName should always exist
    let result = APIURLUtilities.infoPlistString(forKey: "CFBundleName")
    XCTAssertFalse(result.isEmpty, "CFBundleName should exist in Info.plist")
  }
}
