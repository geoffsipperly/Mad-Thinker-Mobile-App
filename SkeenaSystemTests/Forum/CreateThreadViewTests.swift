import XCTest
import SwiftUI
@testable import SkeenaSystem

/// Tests for CreateThreadView functionality.
/// These tests verify the word counting and limiting logic used in the view.
final class CreateThreadViewTests: XCTestCase {

  // MARK: - Word Count Tests

  func testWordCount_emptyString_returnsZero() {
    let count = wordCount("")
    XCTAssertEqual(count, 0)
  }

  func testWordCount_singleWord_returnsOne() {
    let count = wordCount("Hello")
    XCTAssertEqual(count, 1)
  }

  func testWordCount_multipleWords_returnsCorrectCount() {
    let count = wordCount("Hello world this is a test")
    XCTAssertEqual(count, 6)
  }

  func testWordCount_withExtraSpaces_ignoresExtraSpaces() {
    let count = wordCount("Hello    world   test")
    XCTAssertEqual(count, 3)
  }

  func testWordCount_withNewlines_countsWordsAcrossLines() {
    let count = wordCount("Hello\nworld\ntest")
    XCTAssertEqual(count, 3)
  }

  func testWordCount_withMixedWhitespace_countsCorrectly() {
    let count = wordCount("  Hello \n\n world  \t test  ")
    XCTAssertEqual(count, 3)
  }

  // MARK: - Word Limiting Tests

  func testLimited_underLimit_returnsOriginal() {
    let text = "Hello world"
    let result = limited(to: 5, text: text)
    XCTAssertEqual(result, text)
  }

  func testLimited_atLimit_returnsOriginal() {
    let text = "One two three four five"
    let result = limited(to: 5, text: text)
    XCTAssertEqual(result, text)
  }

  func testLimited_overLimit_truncates() {
    let text = "One two three four five six seven"
    let result = limited(to: 5, text: text)
    XCTAssertEqual(result, "One two three four five")
  }

  func testLimited_emptyString_returnsEmpty() {
    let result = limited(to: 5, text: "")
    XCTAssertEqual(result, "")
  }

  func testLimited_withExtraSpaces_normalizesSpaces() {
    let text = "One   two    three"
    let result = limited(to: 2, text: text)
    XCTAssertEqual(result, "One two")
  }

  // MARK: - Helper Functions (mirroring CreateThreadView logic)

  /// Mirrors the wordCount function from CreateThreadView
  private func wordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
  }

  /// Mirrors the limited function from CreateThreadView
  private func limited(to maxWords: Int, text: String) -> String {
    let parts = text.split { $0.isWhitespace || $0.isNewline }
    if parts.count <= maxWords { return text }
    return parts.prefix(maxWords).joined(separator: " ")
  }
}
