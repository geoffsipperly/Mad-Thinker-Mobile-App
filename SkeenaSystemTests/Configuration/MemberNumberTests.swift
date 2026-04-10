//
//  MemberNumberTests.swift
//  SkeenaSystemTests
//

import XCTest
@testable import SkeenaSystem

final class MemberNumberTests: XCTestCase {

  // MARK: - Normalization

  func testNormalize_uppercases() {
    XCTAssertEqual(MemberNumber.normalize("mad4zq7h9"), "MAD4ZQ7H9")
  }

  func testNormalize_stripsSpaces() {
    XCTAssertEqual(MemberNumber.normalize("MAD 4ZQ 7H9"), "MAD4ZQ7H9")
  }

  func testNormalize_stripsHyphens() {
    XCTAssertEqual(MemberNumber.normalize("MAD-4ZQ-7H9"), "MAD4ZQ7H9")
  }

  func testNormalize_crockfordErrorCorrection_I_to_1() {
    XCTAssertEqual(MemberNumber.normalize("MADI4ZQ7H9"), "MAD14ZQ7H9")
  }

  func testNormalize_crockfordErrorCorrection_L_to_1() {
    XCTAssertEqual(MemberNumber.normalize("MADL4ZQ7H9"), "MAD14ZQ7H9")
  }

  func testNormalize_crockfordErrorCorrection_O_to_0() {
    XCTAssertEqual(MemberNumber.normalize("MADO4ZQ7H9"), "MAD04ZQ7H9")
  }

  func testNormalize_combinedErrors() {
    // lowercase + spaces + Crockford substitutions
    XCTAssertEqual(MemberNumber.normalize("mad 4zq-7h9"), "MAD4ZQ7H9")
  }

  // MARK: - Validation

  func testIsValid_correctFormat() {
    XCTAssertTrue(MemberNumber.isValid("MAD4ZQ7H9"))
    XCTAssertTrue(MemberNumber.isValid("MADR3KW5N"))
    XCTAssertTrue(MemberNumber.isValid("MAD8BTXG2"))
  }

  func testIsValid_normalizesBeforeValidating() {
    XCTAssertTrue(MemberNumber.isValid("mad4zq7h9"))
    XCTAssertTrue(MemberNumber.isValid("MAD-4ZQ-7H9"))
  }

  func testIsValid_rejectsWrongPrefix() {
    XCTAssertFalse(MemberNumber.isValid("BAD4ZQ7H9"))
  }

  func testIsValid_rejectsWrongLength() {
    XCTAssertFalse(MemberNumber.isValid("MAD4ZQ"))
    XCTAssertFalse(MemberNumber.isValid("MAD4ZQ7H9X"))
  }

  func testIsValid_rejectsExcludedChars() {
    // U is excluded from Crockford Base32
    XCTAssertFalse(MemberNumber.isValid("MAD4ZQUH9"))
  }
}
