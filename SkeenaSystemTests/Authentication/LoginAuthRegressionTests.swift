//
//  LoginAuthRegressionTests.swift
//  EpicWatersTests
//
//  Created by Codex on <date>
//

import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class LoginAuthRegressionTests: XCTestCase {

  // MARK: - Setup / Helpers

  override func setUp() {
    super.setUp()
    clearAuthKeychainEntries()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil

    // Fresh AuthService per test
    AuthService.resetSharedForTests()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearAuthKeychainEntries()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
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
      let q: [CFString: Any] = [ kSecClass: kSecClassGenericPassword, kSecAttrAccount: account ]
      SecItemDelete(q as CFDictionary)
    }
  }

  @discardableResult
  private func setKeychain(account: String, value: String) -> Bool {
    let del: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account
    ]
    SecItemDelete(del as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    let add: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account,
      kSecValueData: data
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    return status == errSecSuccess
  }

  private func getKeychain(account: String) -> String? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne
    ]
    var res: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &res)
    if status == errSecSuccess, let data = res as? Data, let s = String(data: data, encoding: .utf8) {
      return s
    }
    return nil
  }

  private func setAccessToken(_ token: String, expiresInSeconds: Int = 3600) {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: token)
    if expiresInSeconds > 0 {
      let exp = Int(Date().timeIntervalSince1970) + expiresInSeconds
      _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: String(exp))
    } else {
      // remove stored expiry to force JWT-decoding path
      let delQuery: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: "epicwaters.auth.access_token_exp"
      ]
      SecItemDelete(delQuery as CFDictionary)
    }
  }

  private func setRefreshToken(_ token: String) {
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: token)
  }

  // Helper to detect refresh requests in Mock handler
  private func requestIsRefresh(_ request: URLRequest) -> Bool {
    if let url = request.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
       comps.queryItems?.contains(where: { $0.name == "grant_type" && $0.value == "refresh_token" }) == true {
      return true
    }
    if let body = request.httpBody, let s = String(data: body, encoding: .utf8),
       s.contains("grant_type=refresh_token") {
      return true
    }
    return false
  }

  // MARK: - Tests: Sign-up (happy paths)

  func testGuideSignUp_success_publishesGuideRole_and_authenticated() async throws {
    // signup 201, token 200, profile 200 (guide)
    let signupResponse = Data("{}".utf8)
    let tokenJSON: [String: Any] = [
      "access_token":"signup-guide-token",
      "refresh_token":"signup-guide-refresh",
      "expires_in": 3600,
      "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = [
      "id":"g1",
      "email":"g@example.com",
      "user_metadata":["first_name":"G","user_type":"guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, signupResponse)
      } else if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signUp(email: "g@example.com", password: "password", firstName: "G", lastName: "U", userType: .guide, community: "Bend Fly Shop")
    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentUserType, .guide)
    XCTAssertEqual(auth.currentFirstName, "G")
    XCTAssertNotNil(getKeychain(account: "epicwaters.auth.access_token"))
  }

  func testAnglerSignUp_success_requiresAnglerNumber_and_publishesAnglerRole() async throws {
    let signupResponse = Data("{}".utf8)
    let tokenJSON: [String: Any] = [
      "access_token":"signup-angler-token",
      "refresh_token":"signup-angler-refresh",
      "expires_in": 3600,
      "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = [
      "id":"a1",
      "email":"a@example.com",
      "user_metadata":["first_name":"A","user_type":"angler","angler_number":"12345"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, signupResponse)
      } else if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signUp(email: "a@example.com", password: "pw", firstName: "A", lastName: "L", userType: .angler, community: "Bend Fly Shop", anglerNumber: "12345")
    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentUserType, .angler)
    XCTAssertEqual(auth.currentAnglerNumber, "12345")
  }

  // MARK: - Sign-up validation & negative paths

  func testSignUp_missingFirstName_throwsValidationError() async throws {
    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "x@x.com", password: "p", firstName: "", lastName: "L", userType: .guide, community: "C")
      XCTFail("Expected validation error")
    } catch {
      XCTAssert(error is AuthService.InputValidationError)
    }
  }

  func testSignUp_anglerMissingAnglerNumber_throwsValidationError() async throws {
    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "angler@x", password: "p", firstName: "A", lastName: "B", userType: .angler, community: "C", anglerNumber: nil)
      XCTFail("Expected validation error for anglerNumber")
    } catch {
      XCTAssert(error is AuthService.InputValidationError)
    }
  }

  func testSignUp_anglerNumber_invalidFormat_throwsValidationError() async throws {
    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "angler@x", password: "p", firstName: "A", lastName: "B", userType: .angler, community: "C", anglerNumber: "12ab")
      XCTFail("Expected validation error for invalid angler number")
    } catch {
      XCTAssert(error is AuthService.InputValidationError)
    }
  }

  func testSignUp_duplicateEmail_returnsHttpError() async throws {
    // Mock server 400/409
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        let body = #"{"msg":"email exists"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "dup@example.com", password: "p", firstName: "D", lastName: "U", userType: .guide, community: "C")
      XCTFail("Expected http error for duplicate")
    } catch {
      XCTAssert(error is AuthService.AuthError)
    }
  }

  func testSignUp_longNames_and_specialChars_accepts() async throws {
    // Mock success (signup -> token -> user)
    let tokenJSON: [String: Any] = [
      "access_token":"longname-token",
      "refresh_token":"longname-refresh",
      "expires_in":3600,
      "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = [
      "id":"u-long",
      "email":"long@example.com",
      "user_metadata":["first_name":"Łŕøg-😀","user_type":"guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      } else if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signUp(email: "long@example.com", password: "pw", firstName: "Łŕøg-😀", lastName: "User", userType: .guide, community: "C")
    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentFirstName, "Łŕøg-😀")
  }

  func testSignUp_emailConfirmationRequired_signInFailsWith403() async throws {
    // signUp 201, signIn returns 403
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      } else if url.path.contains("/auth/v1/token") {
        let body = #"{"msg":"confirmation required"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "confirm@example.com", password: "pw", firstName: "C", lastName: "U", userType: .guide, community: "C")
      XCTFail("Expected signIn to fail due to confirmation requirement")
    } catch {
      XCTAssertTrue(true)
    }
  }

  // MARK: - Login (sign-in)

  func testSignIn_success_storesTokens_and_publishesProfile() async throws {
    let tokenJSON: [String: Any] = [
      "access_token":"signin-token",
      "refresh_token":"signin-refresh",
      "expires_in":3600,
      "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = [
      "id":"u-s",
      "email":"s@example.com",
      "user_metadata":["first_name":"S","user_type":"guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signIn(email: "s@example.com", password: "pw")
    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentUserType, .guide)
    XCTAssertEqual(getKeychain(account: "epicwaters.auth.access_token"), "signin-token")
  }

  func testSignIn_wrongPassword_returns401_and_notAuthenticated() async throws {
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        let body = #"{"msg":"Invalid credentials"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    do {
      try await auth.signIn(email: "no@example.com", password: "bad")
      XCTFail("Expected 401")
    } catch {
      XCTAssertTrue(true)
    }
    XCTAssertFalse(auth.isAuthenticated)
  }

  func testSignIn_offlineFallback_withCachedCredentials() async throws {
    UserDefaults.standard.set("offlineu@example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "offlinepw")

    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    let auth = AuthService.shared
    try await auth.signIn(email: "offlineu@example.com", password: "offlinepw")
    XCTAssertTrue(auth.isAuthenticated)
  }

  func testSignIn_offlineFallback_withoutCachedCredentials_fails() async throws {
    // Ensure no offline
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    let auth = AuthService.shared
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    do {
      try await auth.signIn(email: "nooffline@example.com", password: "nope")
      XCTFail("Expected offline sign-in to fail")
    } catch {
      if let authErr = error as? AuthService.AuthError {
        XCTAssertEqual(authErr, .networkUnavailable)
      } else {
        XCTFail("Expected AuthService.AuthError.networkUnavailable; got: \(error)")
      }
    }
  }

  func testPasswordReset_request_succeeds_and_fails() async throws {
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/recover") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    let auth = AuthService.shared
    try await auth.requestPasswordReset(email: "any@example.com")

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/recover") {
        let body = #"{"msg":"bad"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    do {
      try await auth.requestPasswordReset(email: "any@example.com")
      XCTFail("Expected reset to fail")
    } catch {
      XCTAssertTrue(true)
    }
  }

  // MARK: - Token behavior & concurrency

  func testPersistTokens_updateReplacesOldToken() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: String(Int(Date().timeIntervalSince1970 + 10)))

    let tokenJSON: [String: Any] = [
      "access_token": "new-token-xyz", "refresh_token": "new-refresh-abc", "expires_in": 3600, "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id":"u1","email":"x@x.com"]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signIn(email: "a@b.com", password: "pw")
    XCTAssertEqual(getKeychain(account: "epicwaters.auth.access_token"), "new-token-xyz")
  }

  func testCurrentAccessToken_refreshesWhenExpired_andKeychainUpdated() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: "1")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-abc")

    let refreshedJSON: [String: Any] = [
      "access_token":"refreshed-token-123","refresh_token":"refreshed-refresh-456","expires_in":3600,"token_type":"bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshedJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token"), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
         comps.queryItems?.contains(where: { $0.name == "grant_type" && $0.value == "refresh_token" }) == true {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    let token = await auth.currentAccessToken()
    XCTAssertEqual(token, "refreshed-token-123")
    XCTAssertEqual(getKeychain(account: "epicwaters.auth.access_token"), "refreshed-token-123")
  }

  func testConcurrentRefresh_onlyOneNetworkCall() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: "1")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-abc")

    var refreshCallCount = 0
    let counterQ = DispatchQueue(label: "counter")

    let refreshedJSON: [String: Any] = [
      "access_token":"concurrent-refreshed-token","refresh_token":"concurrent-refreshed-refresh","expires_in":3600,"token_type":"bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshedJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token"), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
         comps.queryItems?.contains(where: { $0.name == "grant_type" && $0.value == "refresh_token" }) == true {
        counterQ.sync { refreshCallCount += 1 }
        Thread.sleep(forTimeInterval: 0.25)
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    let responses = await withTaskGroup(of: String?.self) { group -> [String?] in
      for _ in 0..<6 {
        group.addTask { await auth.currentAccessToken() }
      }
      var out: [String?] = []
      for await r in group { out.append(r) }
      return out
    }

    XCTAssertTrue(responses.allSatisfy { $0 == "concurrent-refreshed-token" })
    XCTAssertEqual(refreshCallCount, 1)
  }

  func testConcurrentSignIn_multipleCalls_resultInLastWriteWins_butNoCrash() async throws {
    let tokenJSON: [String: Any] = [
      "access_token":"concurrent-signin-token",
      "refresh_token":"concurrent-signin-refresh",
      "expires_in":3600,
      "token_type":"bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id":"u","email":"c@c.com"]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        Thread.sleep(forTimeInterval: 0.2)
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<5 {
        group.addTask {
          try? await auth.signIn(email: "concurrent@x.com", password: "pw")
        }
      }
      await group.waitForAll()
    }

    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(getKeychain(account: "epicwaters.auth.access_token"), "concurrent-signin-token")
  }

  func testResumeSessionIfPossible_refreshAndProfile() async throws {
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-ok")
    let refreshed: [String: Any] = [
      "access_token":"resume-token","refresh_token":"resume-refresh","expires_in":3600,"token_type":"bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshed, options: [])
    let userJSON: [String: Any] = [
      "id":"u-resume",
      "email":"r@r.com",
      "user_metadata":["first_name":"Resume","user_type":"guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    let ok = await auth.resumeSessionIfPossible()
    XCTAssertTrue(ok)
    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentUserType, .guide)
  }

  // MARK: - Profile & role-specific tests

  func testLoadUserProfile_parsesAnglerMetadata_andPublishes_fields() async throws {
    setAccessToken("valid-token", expiresInSeconds: 3600)
    let userJSON: [String: Any] = [
      "id":"u-angler","email":"ang@example.com",
      "user_metadata":["first_name":"Terry", "user_type":"angler", "angler_number": 98765]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    await auth.loadUserProfile()
    XCTAssertEqual(auth.currentUserType, .angler)
    XCTAssertEqual(auth.currentFirstName, "Terry")
    XCTAssertEqual(auth.currentAnglerNumber, "98765")
  }

  func testLoadUserProfile_missingUserMetadata_clearsFields() async throws {
    setAccessToken("valid-token", expiresInSeconds: 3600)
    let userJSON: [String: Any] = ["id":"u-nometa","email":"no@meta.com"]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    await auth.loadUserProfile()
    XCTAssertNil(auth.currentFirstName)
    XCTAssertNil(auth.currentUserType)
    XCTAssertNil(auth.currentAnglerNumber)
  }

  // MARK: - Security / Edge cases

  func testSignUp_sqlInjection_likeInput_isHandled() async throws {
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        // server rejects suspicious input
        let body = #"{"msg":"bad input"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    let auth = AuthService.shared
    do {
      try await auth.signUp(email: "x'; DROP TABLE --@x", password: "p", firstName: "X", lastName: "Y", userType: .guide, community: "C")
      XCTFail("Expected server to reject bad input")
    } catch {
      XCTAssertTrue(error is AuthService.AuthError)
    }
  }

  func testRateLimit_signUpOrSignIn_429_handling() async throws {
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") || url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    let auth = AuthService.shared
    do {
      try await auth.signIn(email: "rate@limit.com", password: "p")
      XCTFail("Expected rate limit error")
    } catch {
      XCTAssertTrue(error is AuthService.AuthError)
    }
  }

  func testLongStrings_andUnicode_inNames_supported() async throws {
    let tokenJSON: [String: Any] = ["access_token":"tok","refresh_token":"r","expires_in":3600,"token_type":"bearer"]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id":"u","email":"u@u.com","user_metadata":["first_name":String(repeating: "𐍈", count: 200), "user_type":"guide"]]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/signup") {
        return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      } else if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    try await auth.signUp(email: "u@u.com", password: "p", firstName: String(repeating: "𐍈", count: 200), lastName: "L", userType: .guide, community: "C")
    XCTAssertTrue(auth.isAuthenticated)
  }

  // MARK: - Misc / maintenance

  func testTokenExpirationBuffer_behavior() async throws {
    // Token with exp 25s in the future -> should be considered invalid (120s buffer)
    let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString()
      .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    let exp25 = Int(Date().timeIntervalSince1970 + 25)
    let payload25 = try JSONSerialization.data(withJSONObject: ["exp": exp25], options: []).base64EncodedString()
      .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    let jwt25 = "\(header).\(payload25).sig"
    setAccessToken(jwt25, expiresInSeconds: 0)
    let auth = AuthService.shared
    let t25 = await auth.currentAccessToken()
    XCTAssertNil(t25)

    // Token with exp 150s in future -> valid (past 120s buffer)
    let exp150 = Int(Date().timeIntervalSince1970 + 150)
    let payload150 = try JSONSerialization.data(withJSONObject: ["exp": exp150], options: []).base64EncodedString()
      .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    let jwt150 = "\(header).\(payload150).sig"
    setAccessToken(jwt150, expiresInSeconds: 0)
    let t150 = await auth.currentAccessToken()
    XCTAssertEqual(t150, jwt150)
  }

  func testSignOut_clearsTokensAndAuthStore() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "signout-token")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "signout-refresh")
    let auth = AuthService.shared
    await auth.signOut()
    XCTAssertNil(getKeychain(account: "epicwaters.auth.access_token"))
    XCTAssertNil(getKeychain(account: "epicwaters.auth.refresh_token"))
  }
}

