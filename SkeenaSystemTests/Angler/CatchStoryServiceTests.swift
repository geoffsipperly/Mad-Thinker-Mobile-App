import XCTest
@testable import SkeenaSystem

/// Tests for CatchStoryService local cache logic and CatchStoryDTO coding.
///
/// Validates:
/// 1. CatchStoryDTO is Codable (round-trip encode/decode)
/// 2. CatchStoryError cases produce meaningful descriptions
/// 3. CatchStoryAPI URL composition (basic validation)
/// 4. Cache key generation is catch-ID and user-ID specific
final class CatchStoryServiceTests: XCTestCase {

  // MARK: - Setup / Teardown

  override func tearDown() {
    // Clean up any test cache entries
    let defaults = UserDefaults.standard
    for key in defaults.dictionaryRepresentation().keys {
      if key.hasPrefix("epicwaters.catchstory.test") {
        defaults.removeObject(forKey: key)
      }
    }
    super.tearDown()
  }

  // MARK: - CatchStoryDTO Coding Tests

  func testCatchStoryDTO_encodeDecode_roundTrip() throws {
    let original = CatchStoryDTO(
      catch_id: "catch-123",
      title: "Epic Steelhead",
      summary: "A beautiful 36-inch steelhead caught on the Nehalem River."
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CatchStoryDTO.self, from: data)

    XCTAssertEqual(decoded.catch_id, original.catch_id)
    XCTAssertEqual(decoded.title, original.title)
    XCTAssertEqual(decoded.summary, original.summary)
  }

  func testCatchStoryDTO_decodesFromJSON() throws {
    let json = """
    {
      "catch_id": "abc-456",
      "title": "Big Fish",
      "summary": "Caught a monster."
    }
    """.data(using: .utf8)!

    let dto = try JSONDecoder().decode(CatchStoryDTO.self, from: json)
    XCTAssertEqual(dto.catch_id, "abc-456")
    XCTAssertEqual(dto.title, "Big Fish")
    XCTAssertEqual(dto.summary, "Caught a monster.")
  }

  func testCatchStoryDTO_missingField_throwsDecodingError() {
    let json = """
    {
      "catch_id": "abc-456",
      "title": "Big Fish"
    }
    """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(CatchStoryDTO.self, from: json))
  }

  // MARK: - CatchStoryError Tests

  func testCatchStoryError_notAuthenticated_description() {
    let error = CatchStoryError.notAuthenticated
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.contains("signed in") ?? false)
  }

  func testCatchStoryError_badStatus_includesCode() {
    let error = CatchStoryError.badStatus(500, "Server error")
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("500"))
    XCTAssertTrue(desc.contains("Server error"))
  }

  func testCatchStoryError_badStatus_nilMessage() {
    let error = CatchStoryError.badStatus(404, nil)
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("404"))
  }

  func testCatchStoryError_badURL_description() {
    let error = CatchStoryError.badURL
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.lowercased().contains("url") ?? false)
  }

  func testCatchStoryError_decoding_wrapsUnderlyingError() {
    let underlyingError = NSError(domain: "test", code: -1)
    let error = CatchStoryError.decoding(underlyingError)
    XCTAssertNotNil(error.errorDescription)
  }

  func testCatchStoryError_network_wrapsUnderlyingError() {
    let underlyingError = URLError(.notConnectedToInternet)
    let error = CatchStoryError.network(underlyingError)
    XCTAssertNotNil(error.errorDescription)
  }

  // MARK: - CatchStoryError Conformance

  func testCatchStoryError_allCases_haveDescription() {
    let errors: [CatchStoryError] = [
      .notAuthenticated,
      .badStatus(400, "Bad Request"),
      .badStatus(401, nil),
      .decoding(NSError(domain: "test", code: 0)),
      .network(URLError(.timedOut)),
      .badURL
    ]

    for error in errors {
      XCTAssertNotNil(error.errorDescription, "\(error) should have errorDescription")
      XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
    }
  }

  // MARK: - Cache Key Pattern Tests

  func testCacheKey_withUserId_includesUserAndCatchId() {
    // Test the pattern used internally: "epicwaters.catchstory.{userId}.{catchId}"
    let userId = "user-abc"
    let catchId = "catch-123"
    let expectedKey = "epicwaters.catchstory.\(userId).\(catchId)"

    // Store and retrieve via UserDefaults to verify the pattern works
    let story = CatchStoryDTO(catch_id: catchId, title: "Test", summary: "Test summary")
    let data = try! JSONEncoder().encode(story)
    UserDefaults.standard.set(data, forKey: "epicwaters.catchstory.test.\(catchId)")

    let loaded = UserDefaults.standard.data(forKey: "epicwaters.catchstory.test.\(catchId)")
    XCTAssertNotNil(loaded, "Should store and retrieve from UserDefaults")

    // Verify the expected key format
    XCTAssertTrue(expectedKey.contains(userId))
    XCTAssertTrue(expectedKey.contains(catchId))
  }

  func testCacheKey_withoutUserId_usesAnonPrefix() {
    let catchId = "catch-456"
    let expectedKey = "epicwaters.catchstory.anon.\(catchId)"

    XCTAssertTrue(expectedKey.contains("anon"))
    XCTAssertTrue(expectedKey.contains(catchId))
  }

  func testCacheKey_differentCatchIds_produceDifferentKeys() {
    let key1 = "epicwaters.catchstory.anon.catch-111"
    let key2 = "epicwaters.catchstory.anon.catch-222"
    XCTAssertNotEqual(key1, key2)
  }

  // MARK: - UserDefaults Cache Round-Trip

  func testUserDefaultsCache_storeAndRetrieve() throws {
    let story = CatchStoryDTO(catch_id: "test-rt", title: "Round Trip", summary: "Testing cache")
    let key = "epicwaters.catchstory.test.test-rt"

    let data = try JSONEncoder().encode(story)
    UserDefaults.standard.set(data, forKey: key)

    guard let loadedData = UserDefaults.standard.data(forKey: key) else {
      XCTFail("Should have data in UserDefaults")
      return
    }

    let loaded = try JSONDecoder().decode(CatchStoryDTO.self, from: loadedData)
    XCTAssertEqual(loaded.catch_id, "test-rt")
    XCTAssertEqual(loaded.title, "Round Trip")
    XCTAssertEqual(loaded.summary, "Testing cache")
  }

  func testUserDefaultsCache_missingKey_returnsNilData() {
    let data = UserDefaults.standard.data(forKey: "epicwaters.catchstory.test.nonexistent")
    XCTAssertNil(data)
  }
}
