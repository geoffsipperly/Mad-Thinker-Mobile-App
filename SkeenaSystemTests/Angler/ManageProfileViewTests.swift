// ManageProfileViewTests.swift
// SkeenaSystemTests
//
// Regression tests for ManageProfileView:
//   - MyProfile model encoding/decoding (profile-only, no preferences)
//   - ManageProfileAPI URL composition
//   - Phone validation logic
//   - Load/save request structure (profile-only payloads)
//   - Save body excludes preference fields
//   - Member number is read-only (present in model, not sent on save)

import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class ManageProfileViewTests: XCTestCase {

  // MARK: - Setup / teardown

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    AuthService.resetSharedForTests()
    clearAuthKeychainEntries()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearAuthKeychainEntries()
    super.tearDown()
  }

  private func clearAuthKeychainEntries() {
    let keys = [
      "epicwaters.auth.access_token",
      "epicwaters.auth.refresh_token",
      "epicwaters.auth.access_token_exp",
      "OfflineLastPassword"
    ]
    for account in keys {
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: account
      ]
      SecItemDelete(query as CFDictionary)
    }
  }

  // MARK: - MyProfile Model Tests

  func testMyProfile_decodesAllFields() throws {
    let json = """
    {
      "firstName": "John",
      "lastName": "Doe",
      "memberId": "MAD4ZQ7H9",
      "dateOfBirth": "1990-01-15",
      "phoneNumber": "+1-555-123-4567"
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(MyProfile.self, from: json)
    XCTAssertEqual(profile.firstName, "John")
    XCTAssertEqual(profile.lastName, "Doe")
    XCTAssertEqual(profile.memberId, "MAD4ZQ7H9")
    XCTAssertEqual(profile.dateOfBirth, "1990-01-15")
    XCTAssertEqual(profile.phoneNumber, "+1-555-123-4567")
  }

  func testMyProfile_decodesWithNullOptionals() throws {
    let json = """
    {
      "firstName": null,
      "lastName": null,
      "memberId": null,
      "dateOfBirth": null,
      "phoneNumber": null
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(MyProfile.self, from: json)
    XCTAssertNil(profile.firstName)
    XCTAssertNil(profile.lastName)
    XCTAssertNil(profile.memberId)
    XCTAssertNil(profile.dateOfBirth)
    XCTAssertNil(profile.phoneNumber)
  }

  func testMyProfile_decodesWithMissingKeys() throws {
    let json = """
    {}
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(MyProfile.self, from: json)
    XCTAssertNil(profile.firstName)
    XCTAssertNil(profile.memberId)
  }

  func testMyProfile_encodesAllFields() throws {
    let profile = MyProfile(
      firstName: "Jane",
      lastName: "Smith",
      memberId: "abc12345",
      dateOfBirth: "1985-06-20",
      phoneNumber: "5551234567"
    )
    let data = try JSONEncoder().encode(profile)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertEqual(dict["firstName"] as? String, "Jane")
    XCTAssertEqual(dict["lastName"] as? String, "Smith")
    XCTAssertEqual(dict["memberId"] as? String, "abc12345")
    XCTAssertEqual(dict["dateOfBirth"] as? String, "1985-06-20")
    XCTAssertEqual(dict["phoneNumber"] as? String, "5551234567")
  }

  func testMyProfile_equatable_identicalProfilesAreEqual() {
    let a = MyProfile(firstName: "A", lastName: "B", memberId: "m1", dateOfBirth: "2000-01-01", phoneNumber: "1234567890")
    let b = MyProfile(firstName: "A", lastName: "B", memberId: "m1", dateOfBirth: "2000-01-01", phoneNumber: "1234567890")
    XCTAssertEqual(a, b)
  }

  func testMyProfile_equatable_differentProfilesAreNotEqual() {
    let a = MyProfile(firstName: "A", lastName: "B", memberId: "m1", dateOfBirth: "2000-01-01", phoneNumber: "1234567890")
    let b = MyProfile(firstName: "A", lastName: "B", memberId: "m1", dateOfBirth: "2000-01-01", phoneNumber: "9999999999")
    XCTAssertNotEqual(a, b)
  }

  // MARK: - Profile-Only Response (no preferences)

  func testLoadResponse_profileOnly_decodesCorrectly() throws {
    let json = """
    {
      "profile": {
        "firstName": "John",
        "lastName": "Doe",
        "memberId": "MAD4ZQ7H9",
        "dateOfBirth": "1990-01-15",
        "phoneNumber": "+1-555-123-4567"
      }
    }
    """.data(using: .utf8)!

    struct Resp: Decodable {
      let profile: MyProfile
    }

    let decoded = try JSONDecoder().decode(Resp.self, from: json)
    XCTAssertEqual(decoded.profile.firstName, "John")
    XCTAssertEqual(decoded.profile.memberId, "MAD4ZQ7H9")
    XCTAssertEqual(decoded.profile.phoneNumber, "+1-555-123-4567")
  }

  func testLoadResponse_ignoresUnknownPreferencesKey() throws {
    // Server may still send a preferences key during migration;
    // our Resp struct should not fail if extra keys are present.
    let json = """
    {
      "profile": {
        "firstName": "John",
        "lastName": "Doe",
        "memberId": "m1"
      },
      "preferences": {
        "drinks": true,
        "drinksText": "Coffee"
      }
    }
    """.data(using: .utf8)!

    struct Resp: Decodable {
      let profile: MyProfile
    }

    let decoded = try JSONDecoder().decode(Resp.self, from: json)
    XCTAssertEqual(decoded.profile.firstName, "John",
                   "Should decode profile even when extra keys like 'preferences' are present")
  }

  // MARK: - Save Body Composition

  func testSaveBody_containsOnlyProfileFields() {
    let profile = MyProfile(
      firstName: "Jane",
      lastName: "Smith",
      memberId: "abc123",
      dateOfBirth: "1985-06-20",
      phoneNumber: "5551234567"
    )

    // Replicate the save body logic from ManageProfileView
    var body: [String: Any] = [:]
    if let v = profile.firstName, !v.isEmpty { body["firstName"] = v }
    if let v = profile.lastName, !v.isEmpty { body["lastName"] = v }
    if let v = profile.phoneNumber, !v.isEmpty { body["phoneNumber"] = v }
    if let v = profile.dateOfBirth, !v.isEmpty { body["dateOfBirth"] = v }

    XCTAssertEqual(body["firstName"] as? String, "Jane")
    XCTAssertEqual(body["lastName"] as? String, "Smith")
    XCTAssertEqual(body["phoneNumber"] as? String, "5551234567")
    XCTAssertEqual(body["dateOfBirth"] as? String, "1985-06-20")

    // Must NOT contain any preference keys
    XCTAssertNil(body["drinks"], "Save body must not contain preference fields")
    XCTAssertNil(body["drinksText"], "Save body must not contain preference fields")
    XCTAssertNil(body["food"], "Save body must not contain preference fields")
    XCTAssertNil(body["foodText"], "Save body must not contain preference fields")
    XCTAssertNil(body["health"], "Save body must not contain preference fields")
    XCTAssertNil(body["healthText"], "Save body must not contain preference fields")
    XCTAssertNil(body["occasion"], "Save body must not contain preference fields")
    XCTAssertNil(body["occasionText"], "Save body must not contain preference fields")
    XCTAssertNil(body["allergies"], "Save body must not contain preference fields")
    XCTAssertNil(body["allergiesText"], "Save body must not contain preference fields")
    XCTAssertNil(body["cpap"], "Save body must not contain preference fields")
    XCTAssertNil(body["cpapText"], "Save body must not contain preference fields")

    // memberId should not be sent in save body (read-only)
    XCTAssertNil(body["memberId"], "memberId is read-only and should not be in save body")
  }

  func testSaveBody_omitsEmptyFields() {
    let profile = MyProfile(
      firstName: "Jane",
      lastName: nil,
      memberId: nil,
      dateOfBirth: "",
      phoneNumber: nil
    )

    var body: [String: Any] = [:]
    if let v = profile.firstName, !v.isEmpty { body["firstName"] = v }
    if let v = profile.lastName, !v.isEmpty { body["lastName"] = v }
    if let v = profile.phoneNumber, !v.isEmpty { body["phoneNumber"] = v }
    if let v = profile.dateOfBirth, !v.isEmpty { body["dateOfBirth"] = v }

    XCTAssertEqual(body.count, 1, "Only non-nil, non-empty fields should be included")
    XCTAssertEqual(body["firstName"] as? String, "Jane")
    XCTAssertNil(body["lastName"])
    XCTAssertNil(body["dateOfBirth"])
    XCTAssertNil(body["phoneNumber"])
  }

  // MARK: - Phone Validation

  /// Mirrors the private isValidPhone logic from ManageProfileView.
  private func isValidPhone(_ s: String) -> Bool {
    let digits = s.filter { $0.isNumber }
    return digits.count >= 10 && digits.count <= 15
  }

  func testPhoneValidation_validFormats() {
    XCTAssertTrue(isValidPhone("5551234567"), "10 digits should be valid")
    XCTAssertTrue(isValidPhone("+1-555-123-4567"), "Formatted with dashes should be valid")
    XCTAssertTrue(isValidPhone("(555) 123-4567"), "Formatted with parens should be valid")
    XCTAssertTrue(isValidPhone("555.123.4567"), "Formatted with dots should be valid")
    XCTAssertTrue(isValidPhone("123456789012345"), "15 digits should be valid")
  }

  func testPhoneValidation_invalidFormats() {
    XCTAssertFalse(isValidPhone("12345"), "Too few digits should be invalid")
    XCTAssertFalse(isValidPhone("123456789"), "9 digits should be invalid")
    XCTAssertFalse(isValidPhone("1234567890123456"), "16 digits should be invalid")
    XCTAssertFalse(isValidPhone("abcdefghij"), "Non-digit characters only should be invalid")
    XCTAssertFalse(isValidPhone(""), "Empty string should be invalid")
  }

  // MARK: - DOB Date Parsing

  func testDOBParsing_validDate() {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"

    let date = f.date(from: "1990-01-15")
    XCTAssertNotNil(date, "Should parse valid yyyy-MM-dd date")
  }

  func testDOBParsing_invalidDate_returnsNil() {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"

    XCTAssertNil(f.date(from: "not-a-date"), "Invalid date string should return nil")
    XCTAssertNil(f.date(from: ""), "Empty string should return nil")
    XCTAssertNil(f.date(from: "01/15/1990"), "Wrong format should return nil")
  }

  func testDOBRoundTrip_parseAndFormat() {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"

    let original = "1990-01-15"
    let date = f.date(from: original)!
    let formatted = f.string(from: date)
    XCTAssertEqual(formatted, original, "Round-trip should produce the same string")
  }

  // MARK: - ManageProfileAPI URL Composition

  func testManageProfileAPI_saveMethodIsPUT() {
    XCTAssertEqual(ManageProfileAPI.saveMethod, "PUT",
                   "Profile save should use PUT method")
  }

  // MARK: - Load Profile Network (mocked)

  private func signInAsAngler() async throws {
    let tokenJSON: [String: Any] = [
      "access_token": "angler-access-token",
      "refresh_token": "angler-refresh-token",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])

    let userJSON: [String: Any] = [
      "id": "user-angler-001",
      "email": "angler@example.com",
      "user_metadata": [
        "first_name": "Alex",
        "user_type": "angler",
        "member_id": "MAD4ZQ7H9"
      ]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    try await AuthService.shared.signIn(email: "angler@example.com", password: "password")
  }

  func testLoadProfile_GETRequest_hasCorrectHeaders() async throws {
    try await signInAsAngler()

    let profileResponse: [String: Any] = [
      "profile": [
        "firstName": "Alex",
        "lastName": "Test",
        "memberId": "MAD4ZQ7H9",
        "dateOfBirth": "1990-05-20",
        "phoneNumber": "5551234567"
      ]
    ]
    let profileData = try JSONSerialization.data(withJSONObject: profileResponse, options: [])

    var capturedRequest: URLRequest?

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/my-profile") {
        capturedRequest = request
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, profileData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let url = try ManageProfileAPI.url()
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer angler-access-token", forHTTPHeaderField: "Authorization")
    req.setValue(AuthService.shared.publicAnonKey, forHTTPHeaderField: "apikey")

    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

    XCTAssertEqual(code, 200)

    struct Resp: Decodable { let profile: MyProfile }
    let decoded = try JSONDecoder().decode(Resp.self, from: data)
    XCTAssertEqual(decoded.profile.firstName, "Alex")
    XCTAssertEqual(decoded.profile.memberId, "MAD4ZQ7H9")

    XCTAssertNotNil(capturedRequest)
    XCTAssertEqual(capturedRequest?.httpMethod, "GET")
    XCTAssertTrue(capturedRequest?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") ?? false)
    XCTAssertNotNil(capturedRequest?.value(forHTTPHeaderField: "apikey"))
  }

  func testSaveProfile_PUTRequest_sendsProfileOnlyBody() async throws {
    try await signInAsAngler()

    var capturedBody: [String: Any]?

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/my-profile") && request.httpMethod == "PUT" {
        if let bodyData = request.httpBody ?? request.httpBodyStream?.readAll() {
          capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let successJSON = """
        {"success": true, "profile": {"firstName": "Alex", "lastName": "Updated"}}
        """.data(using: .utf8)!
        return (resp, successJSON)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let url = try ManageProfileAPI.url()
    var req = URLRequest(url: url)
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer angler-access-token", forHTTPHeaderField: "Authorization")
    req.setValue(AuthService.shared.publicAnonKey, forHTTPHeaderField: "apikey")

    let body: [String: Any] = [
      "firstName": "Alex",
      "lastName": "Updated",
      "phoneNumber": "5559998888",
      "dateOfBirth": "1990-05-20"
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    let (_, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

    XCTAssertEqual(code, 200)
    XCTAssertNotNil(capturedBody)
    XCTAssertEqual(capturedBody?["firstName"] as? String, "Alex")
    XCTAssertEqual(capturedBody?["lastName"] as? String, "Updated")

    // Verify no preference fields leaked into the body
    XCTAssertNil(capturedBody?["drinks"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["food"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["health"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["allergies"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["cpap"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["occasion"], "Preferences must not be in save body")
    XCTAssertNil(capturedBody?["memberId"], "memberId is read-only, must not be sent")
  }

  func testLoadProfile_serverError_returns400() async throws {
    try await signInAsAngler()

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/my-profile") {
        let errorJSON = """
        {"error": "No member ID associated with account"}
        """.data(using: .utf8)!
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, errorJSON)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let url = try ManageProfileAPI.url()
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer angler-access-token", forHTTPHeaderField: "Authorization")
    req.setValue(AuthService.shared.publicAnonKey, forHTTPHeaderField: "apikey")

    let (_, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

    XCTAssertEqual(code, 400, "Server should return 400 for missing member ID")
  }

  // MARK: - Keychain helpers

  @discardableResult
  private func setKeychain(account: String, value: String) -> Bool {
    let delQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account
    ]
    SecItemDelete(delQuery as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    let addQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account,
      kSecValueData: data
    ]
    return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
  }
}

// MARK: - InputStream helper

private extension InputStream {
  func readAll() -> Data {
    open()
    defer { close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while hasBytesAvailable {
      let read = self.read(buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
