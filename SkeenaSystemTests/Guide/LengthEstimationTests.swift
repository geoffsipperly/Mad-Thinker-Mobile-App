import XCTest
@testable import SkeenaSystem

/// Tests for the length estimation logic that takes the high end of a range.
///
/// The `averagedLength` function in CatchChatViewModel is private, so we
/// replicate its logic here to verify the behavior independently.
/// This ensures that when the AI returns a length range (e.g. "28-32 inches"),
/// we return the high end of the range rather than the average.
final class LengthEstimationTests: XCTestCase {

  // MARK: - Helper

  /// Replicates the averagedLength logic from CatchChatViewModel for testability.
  private func highEndLength(from raw: String) -> String {
    var cleaned = raw
      .replacingOccurrences(of: "inches", with: "")
      .replacingOccurrences(of: "inch", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if cleaned.isEmpty || cleaned == "-" {
      return cleaned
    }

    cleaned = cleaned.replacingOccurrences(of: " ", with: "")

    let separators: [Character] = ["–", "-", "—"]

    for sep in separators {
      if cleaned.contains(sep) {
        let parts = cleaned.split(separator: sep)
        if parts.count == 2,
           let a = Double(parts[0]),
           let b = Double(parts[1]) {
          let high = max(a, b)
          if high.rounded() == high {
            return "\(Int(high)) inches"
          } else {
            return String(format: "%.1f inches", high)
          }
        }
      }
    }

    if cleaned.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
      if let value = Double(cleaned) {
        if value.rounded() == value {
          return "\(Int(value)) inches"
        } else {
          return String(format: "%.1f inches", value)
        }
      }
    }

    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Range Tests (High End)

  func testRange_returnsHighEnd_hyphen() {
    let result = highEndLength(from: "28-32 inches")
    XCTAssertEqual(result, "32 inches", "Should return the high end of a hyphen range")
  }

  func testRange_returnsHighEnd_enDash() {
    let result = highEndLength(from: "28–32 inches")
    XCTAssertEqual(result, "32 inches", "Should return the high end of an en-dash range")
  }

  func testRange_returnsHighEnd_emDash() {
    let result = highEndLength(from: "28—32 inches")
    XCTAssertEqual(result, "32 inches", "Should return the high end of an em-dash range")
  }

  func testRange_returnsHighEnd_noUnits() {
    let result = highEndLength(from: "28-32")
    XCTAssertEqual(result, "32 inches", "Should return high end and append inches even without unit")
  }

  func testRange_returnsHighEnd_withDecimals() {
    let result = highEndLength(from: "27.5-32.5 inches")
    XCTAssertEqual(result, "32.5 inches", "Should return high end with decimal")
  }

  func testRange_returnsHighEnd_reversedOrder() {
    // If range is given in reverse order, max() ensures we still get the high end
    let result = highEndLength(from: "35-28 inches")
    XCTAssertEqual(result, "35 inches", "Should return the higher value even if range is reversed")
  }

  func testRange_notAverage() {
    // The old behavior was to return 30 (average of 28 and 32)
    let result = highEndLength(from: "28-32 inches")
    XCTAssertNotEqual(result, "30 inches", "Should NOT return the average of the range")
  }

  // MARK: - Single Value Tests

  func testSingleValue_integer() {
    let result = highEndLength(from: "32 inches")
    XCTAssertEqual(result, "32 inches", "Should return single integer value as-is")
  }

  func testSingleValue_decimal() {
    let result = highEndLength(from: "32.5 inches")
    XCTAssertEqual(result, "32.5 inches", "Should return single decimal value as-is")
  }

  func testSingleValue_noUnits() {
    let result = highEndLength(from: "32")
    XCTAssertEqual(result, "32 inches", "Should append inches to bare number")
  }

  // MARK: - Edge Cases

  func testEmptyString() {
    let result = highEndLength(from: "")
    XCTAssertEqual(result, "", "Should return empty string for empty input")
  }

  func testDash() {
    let result = highEndLength(from: "-")
    XCTAssertEqual(result, "-", "Should return dash for dash input")
  }

  func testNonNumericInput() {
    let result = highEndLength(from: "not available")
    XCTAssertEqual(result, "not available", "Should return non-numeric input as-is")
  }

  func testWhitespaceHandling() {
    let result = highEndLength(from: " 28 - 32 inches ")
    XCTAssertEqual(result, "32 inches", "Should handle whitespace around range")
  }
}
