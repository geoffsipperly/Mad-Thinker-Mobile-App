import XCTest
@testable import SkeenaSystem

/// Tests for DateParsingUtilities shared date normalization functions.
///
/// Validates:
/// 1. `normalizeDOBToISO` handles all 8 supported date formats
/// 2. Regex fallback extracts dates from embedded text
/// 3. Edge cases: empty, whitespace, invalid, nil
/// 4. `firstMatch` regex extraction
final class DateParsingUtilitiesTests: XCTestCase {

  // MARK: - normalizeDOBToISO: Standard formats

  func testNormalizeDOB_monthDayCommaYear() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("Jan 15, 1990"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_monthDayYear_noComma() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("Jan 15 1990"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_isoFormat_passthrough() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("1990-01-15"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_slashYMD() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("1990/1/15"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_slashMDY_singleDigit() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("1/15/1990"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_slashMMDDYYYY() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("01/15/1990"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_fullMonthName() {
    // "MMM" should handle abbreviated month names
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("Mar 5, 2000"),
      "2000-03-05"
    )
  }

  func testNormalizeDOB_decemberDate() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("Dec 25, 1985"),
      "1985-12-25"
    )
  }

  // MARK: - normalizeDOBToISO: Edge cases

  func testNormalizeDOB_emptyString_returnsNil() {
    XCTAssertNil(DateParsingUtilities.normalizeDOBToISO(""))
  }

  func testNormalizeDOB_whitespaceOnly_returnsNil() {
    XCTAssertNil(DateParsingUtilities.normalizeDOBToISO("   "))
  }

  func testNormalizeDOB_invalidString_returnsNil() {
    XCTAssertNil(DateParsingUtilities.normalizeDOBToISO("not a date"))
  }

  func testNormalizeDOB_randomText_returnsNil() {
    XCTAssertNil(DateParsingUtilities.normalizeDOBToISO("hello world 123"))
  }

  func testNormalizeDOB_leadingTrailingWhitespace() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("  Jan 15, 1990  "),
      "1990-01-15",
      "Should trim whitespace before parsing"
    )
  }

  // MARK: - normalizeDOBToISO: Regex fallback

  func testNormalizeDOB_embeddedDateWithComma_extractedViaRegex() {
    // The regex fallback matches "MMM d, yyyy" pattern in arbitrary text
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("DOB: Jan 15, 1990 some extra text"),
      "1990-01-15"
    )
  }

  func testNormalizeDOB_embeddedDateWithoutComma_extractedViaRegex() {
    XCTAssertEqual(
      DateParsingUtilities.normalizeDOBToISO("Date of birth: Feb 28 1995 end"),
      "1995-02-28"
    )
  }

  // MARK: - firstMatch Tests

  func testFirstMatch_extractsFullMatch() {
    let result = DateParsingUtilities.firstMatch(
      in: "Hello 12345 world",
      pattern: #"\d+"#,
      group: 0
    )
    XCTAssertEqual(result, "12345")
  }

  func testFirstMatch_extractsCaptureGroup() {
    let result = DateParsingUtilities.firstMatch(
      in: "Name: John Doe",
      pattern: #"Name:\s+(\S+)"#,
      group: 1
    )
    XCTAssertEqual(result, "John")
  }

  func testFirstMatch_noMatch_returnsNil() {
    let result = DateParsingUtilities.firstMatch(
      in: "Hello world",
      pattern: #"\d+"#,
      group: 0
    )
    XCTAssertNil(result)
  }

  func testFirstMatch_invalidRegex_returnsNil() {
    let result = DateParsingUtilities.firstMatch(
      in: "Hello",
      pattern: "[invalid",
      group: 0
    )
    XCTAssertNil(result, "Invalid regex should return nil, not crash")
  }

  func testFirstMatch_emptyText_returnsNil() {
    let result = DateParsingUtilities.firstMatch(
      in: "",
      pattern: #"\d+"#,
      group: 0
    )
    XCTAssertNil(result)
  }

  func testFirstMatch_validCaptureGroup_returnsMatch() {
    // Pattern with a capture group: extract digits after "id="
    let result = DateParsingUtilities.firstMatch(
      in: "user id=42 found",
      pattern: #"id=(\d+)"#,
      group: 1
    )
    XCTAssertEqual(result, "42")
  }

  func testFirstMatch_outOfRangeGroup_returnsNil() {
    // group 1 doesn't exist in this pattern (no capture groups)
    let result = DateParsingUtilities.firstMatch(
      in: "Hello 123",
      pattern: #"\d+"#,
      group: 1
    )
    XCTAssertNil(result, "Out-of-range capture group should return nil, not crash")
  }
}
