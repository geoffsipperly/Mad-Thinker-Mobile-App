import XCTest
@testable import SkeenaSystem

/// Tests for ForumAPI error types and ForumAPIError descriptions.
///
/// Note: ForumAPI's URL composition methods are `private static` and depend on
/// Info.plist values (API_BASE_URL, FORUM_BASE) which are available at runtime.
/// These tests verify the error types and any testable public surface.
///
/// Validates:
/// 1. ForumAPIError cases exist and produce meaningful descriptions
/// 2. ForumAPIError localizedDescription content
/// 3. Error code handling patterns
final class ForumAPITests: XCTestCase {

  // MARK: - ForumAPIError Tests

  func testForumAPIError_invalidURL_description() {
    let error = ForumAPIError.invalidURL
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.contains("URL") ?? false)
  }

  func testForumAPIError_requestFailed_includesCode() {
    let error = ForumAPIError.requestFailed(404)
    XCTAssertTrue(error.errorDescription?.contains("404") ?? false)
  }

  func testForumAPIError_requestFailedWithBody_includesCodeAndBody() {
    let error = ForumAPIError.requestFailedWithBody(code: 500, body: "Internal Server Error")
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("500"), "Should include status code")
    XCTAssertTrue(desc.contains("Internal Server Error"), "Should include body")
  }

  func testForumAPIError_decodingFailed_description() {
    let error = ForumAPIError.decodingFailed
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.contains("decode") ?? false)
  }

  func testForumAPIError_missingAuth_description() {
    let error = ForumAPIError.missingAuth
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.contains("signed in") ?? false)
  }

  // MARK: - Error Conformance

  func testForumAPIError_conformsToLocalizedError() {
    let errors: [ForumAPIError] = [
      .invalidURL,
      .requestFailed(400),
      .requestFailedWithBody(code: 401, body: "Unauthorized"),
      .decodingFailed,
      .missingAuth
    ]

    for error in errors {
      // LocalizedError should provide errorDescription
      XCTAssertNotNil(error.errorDescription, "\(error) should have errorDescription")
      XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
    }
  }

  // MARK: - Status Code Boundary Tests

  func testForumAPIError_variousStatusCodes() {
    let codes = [400, 401, 403, 404, 500, 502, 503]
    for code in codes {
      let error = ForumAPIError.requestFailed(code)
      XCTAssertTrue(error.errorDescription?.contains("\(code)") ?? false,
                     "Error description should include code \(code)")
    }
  }

  func testForumAPIError_requestFailedWithBody_emptyBody() {
    let error = ForumAPIError.requestFailedWithBody(code: 403, body: "")
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("403"), "Should still include code even with empty body")
  }
}
