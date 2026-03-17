import XCTest
import Security
@testable import SkeenaSystem

// Consolidated AuthService regression tests (original + 10 extra).
@MainActor
final class AuthServiceRegressionTests: XCTestCase {

  // MARK: - Mock session (scoped to this test class, avoids global URLProtocol registration)

  private var _mockSession: URLSession?
  private var mockSession: URLSession {
    if _mockSession == nil {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      _mockSession = URLSession(configuration: config)
    }
    return _mockSession!
  }

  // MARK: - Test setup/teardown & helpers

  override func setUp() {
    super.setUp()
    clearAuthKeychainEntries()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    MockURLProtocol.requestHandler = nil
    AuthService.resetSharedForTests(session: mockSession)
  }

  override func tearDown() {
    MockURLProtocol.requestHandler = nil
    _mockSession?.invalidateAndCancel()
    _mockSession = nil
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
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: account
      ]
      SecItemDelete(query as CFDictionary)
    }
  }

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
    let status = SecItemAdd(addQuery as CFDictionary, nil)
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
    if status == errSecSuccess, let d = res as? Data, let s = String(data: d, encoding: .utf8) {
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
        // Ensure no expiry is stored so AuthService will decode the JWT payload if present
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

  // MARK: - Original regression tests (8)

  func testSignInSuccess_setsIsAuthenticated() async throws {
    let tokenJSON: [String: Any] = [
      "access_token": "fake-access-token-abc",
      "refresh_token": "fake-refresh-token-xyz",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])

    let userJSON: [String: Any] = [
      "id": "user-abc",
      "email": "test@example.com",
      "user_metadata": [
        "first_name": "Test",
        "user_type": "guide",
        "angler_number": "12345"
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

    let auth = AuthService.shared
    try await auth.signIn(email: "test@example.com", password: "password")
    XCTAssertTrue(auth.isAuthenticated, "AuthService should be authenticated after successful sign-in")
  }

  func testSignInFailure_throwsOnHttpError() async {
    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        let body = #"{"msg":"Invalid credentials"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    do {
      try await auth.signIn(email: "noone@example.com", password: "wrong")
      XCTFail("Expected signIn to throw for 401")
    } catch {
      XCTAssertTrue(true, "Received expected error")
    }
    XCTAssertFalse(auth.isAuthenticated)
  }

  func testSignUpSuccess_invokesSignIn_andSetsAuthenticated() async throws {
    let signupResponse = Data("{}".utf8)
    let tokenJSON: [String: Any] = [
      "access_token": "signup-access-token",
      "refresh_token": "signup-refresh-token",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = [
      "id": "user-signup",
      "email": "new@example.com",
      "user_metadata": ["first_name":"New", "user_type":"guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
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
    try await auth.signUp(email: "new@example.com", password: "password", firstName: "New", lastName: "User", userType: .guide, community: "Bend Fly Shop")
    XCTAssertTrue(auth.isAuthenticated, "After signUp+signIn, should be authenticated")
  }

  func testOfflineFallback_succeedsWhenNetworkUnavailable() async throws {
    UserDefaults.standard.set("offline@example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "offline-pass")

    MockURLProtocol.requestHandler = { request in
      throw URLError(.notConnectedToInternet)
    }

    let auth = AuthService.shared
    try await auth.signIn(email: "offline@example.com", password: "offline-pass")
    XCTAssertTrue(auth.isAuthenticated, "Offline fallback should authenticate using cached credentials")
  }

  func testRequestPasswordReset_successAndFailure() async throws {
    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/recover") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    let auth = AuthService.shared
    try await auth.requestPasswordReset(email: "any@example.com")

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/recover") {
        let body = #"{"msg":"bad"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    do {
      try await auth.requestPasswordReset(email: "any@example.com")
      XCTFail("Expected password reset to throw on 400")
    } catch {
      XCTAssertTrue(true)
    }
  }

  func testCurrentAccessToken_refreshesWhenExpired() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: "1")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-abc")

    let refreshedJSON: [String: Any] = [
      "access_token": "refreshed-token-123",
      "refresh_token": "refreshed-refresh-456",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshedJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token"), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
         let grant = comps.queryItems?.first(where: { $0.name == "grant_type" })?.value, grant == "refresh_token" {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    let token = await auth.currentAccessToken()
    XCTAssertEqual(token, "refreshed-token-123")
    let stored = getKeychain(account: "epicwaters.auth.access_token")
    XCTAssertEqual(stored, "refreshed-token-123")
  }

  func testConcurrentRefresh_onlyOneNetworkCall() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: "1")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-abc")

    var refreshCallCount = 0
    let counterQueue = DispatchQueue(label: "test.counter")

    let refreshedJSON: [String: Any] = [
      "access_token": "concurrent-refreshed-token",
      "refresh_token": "concurrent-refreshed-refresh",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshedJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }

      if url.path.contains("/auth/v1/token") {
        var isRefresh = false

        // Check for grant_type in URL query items
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let grant = comps.queryItems?.first(where: { $0.name == "grant_type" })?.value,
           grant == "refresh_token" {
          isRefresh = true
        }

        // Also check HTTP body for form-encoded grant_type
        if !isRefresh,
           let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8),
           bodyString.contains("grant_type=refresh_token") {
          isRefresh = true
        }

        if isRefresh {
          counterQueue.sync { refreshCallCount += 1 }
          Thread.sleep(forTimeInterval: 0.2)
          return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData)
        }
      }

      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared

    let responses = await withTaskGroup(of: String?.self) { group -> [String?] in
      for _ in 0..<6 {
        group.addTask {
          return await auth.currentAccessToken()
        }
      }
      var results: [String?] = []
      for await r in group {
        results.append(r)
      }
      return results
    }

    XCTAssertTrue(responses.allSatisfy { $0 == "concurrent-refreshed-token" })
    XCTAssertEqual(refreshCallCount, 1, "Expected only one refresh network call; got \(refreshCallCount)")
  }

  func testSignOutRemote_clearsTokensAndUnauthenticates() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "valid-token")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "valid-refresh")
    let future = String(Int(Date().timeIntervalSince1970 + 3600))
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: future)

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/logout") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    AuthService.shared.rememberMeEnabled = false
    await auth.signOutRemote()

    let access = getKeychain(account: "epicwaters.auth.access_token")
    let refresh = getKeychain(account: "epicwaters.auth.refresh_token")
    XCTAssertNil(access)
    XCTAssertNil(refresh)
    XCTAssertFalse(auth.isAuthenticated)
  }

  // MARK: - Extra tests (10)

  func testRefreshFailure_clearsTokensAndUnauthenticates() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: "1")
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-bad")

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        let body = #"{"code":400,"msg":"invalid refresh"}"#.data(using: .utf8)
        return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let auth = AuthService.shared
    let tok = await auth.currentAccessToken()
    XCTAssertNil(tok)
    XCTAssertNil(getKeychain(account: "epicwaters.auth.access_token"))
    XCTAssertNil(getKeychain(account: "epicwaters.auth.refresh_token"))
    XCTAssertFalse(auth.isAuthenticated)
  }

  func testResumeSessionIfPossible_success() async throws {
    _ = setKeychain(account: "epicwaters.auth.refresh_token", value: "refresh-ok")

    let refreshedJSON: [String: Any] = [
      "access_token": "resume-token",
      "refresh_token": "resume-refresh",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let refreshedData = try JSONSerialization.data(withJSONObject: refreshedJSON, options: [])

    let userJSON: [String: Any] = [
      "id": "user-resume",
      "email": "resume@example.com",
      "user_metadata": ["first_name": "Resume", "user_type": "guide"]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
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

  func testLoadUserProfile_parsesProfileAndPublishesRole() async throws {
    setAccessToken("valid-token", expiresInSeconds: 3600)

    let userJSON: [String: Any] = [
      "id": "user-123",
      "email": "me@example.com",
      "user_metadata": [
        "first_name": "Terry",
        "user_type": "angler",
        "angler_number": "98765"
      ]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
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

  func testPersistTokens_replacesExistingToken() async throws {
    _ = setKeychain(account: "epicwaters.auth.access_token", value: "old-token")
    _ = setKeychain(account: "epicwaters.auth.access_token_exp", value: String(Int(Date().timeIntervalSince1970 + 10)))

    let tokenJSON: [String: Any] = [
      "access_token": "new-token-xyz",
      "refresh_token": "new-refresh-abc",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id": "u1", "email": "x@x.com"]
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

    let auth = AuthService.shared
    try await auth.signIn(email: "a@b.com", password: "pw")
    let stored = getKeychain(account: "epicwaters.auth.access_token")
    XCTAssertEqual(stored, "new-token-xyz")
  }

  func testSignUpValidationFailures() async throws {
      let auth = AuthService.shared

      do {
        try await auth.signUp(email: "a@b.com", password: "p",
                              firstName: "", lastName: "L", userType: .guide, community: "C")
        XCTFail("Expected signUp to throw for missing first name")
      } catch {
        XCTAssert(error is AuthService.InputValidationError)
      }

      // Angler without anglerNumber
      do {
        try await auth.signUp(email: "angler@x", password: "p",
                              firstName: "A", lastName: "B", userType: .angler, community: "C", anglerNumber: nil)
        XCTFail("Expected signUp to throw for missing angler number")
      } catch {
        XCTAssert(error is AuthService.InputValidationError)
      }

  }

  func testIsJWTValid_withDecodedJWT() async throws {
    let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    let exp = Int(Date().timeIntervalSince1970 + 3600)
    let payloadObj: [String: Any] = ["exp": exp]
    let payloadData = try JSONSerialization.data(withJSONObject: payloadObj, options: [])
    var payload = payloadData.base64EncodedString()
    payload = payload.replacingOccurrences(of: "=", with: "")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    let jwt = "\(header).\(payload).sig"
    setAccessToken(jwt, expiresInSeconds: 0)
    let auth = AuthService.shared
    let token = await auth.currentAccessToken()
    XCTAssertEqual(token, jwt)
  }

  func testConcurrentSignIn_noCrash_and_tokenPersisted() async throws {
    let tokenJSON: [String: Any] = [
      "access_token": "concurrent-signin-token",
      "refresh_token": "concurrent-signin-refresh",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id":"u", "email":"c@c.com"]
    let userData = try JSONSerialization.data(withJSONObject: userJSON, options: [])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
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

  func testKeychainFallbackOnUpdate() async throws {
    let account = "epicwaters.auth.access_token"
    let _ = setKeychain(account: account, value: "duplicate-old")

    let tokenJSON: [String: Any] = [
      "access_token": "duplicate-new",
      "refresh_token": "dup-refresh",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON, options: [])
    let userJSON: [String: Any] = ["id":"u","email":"d@d.com"]
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
    try await auth.signIn(email: "dup@x", password: "pw")
    XCTAssertEqual(getKeychain(account: "epicwaters.auth.access_token"), "duplicate-new")
  }

  func testSignUpAnglerNumberRequired() async throws {
      let auth = AuthService.shared
      do {
        try await auth.signUp(email: "a@b", password: "p", firstName: "F", lastName: "L",
                              userType: .angler, community: "C", anglerNumber: nil)
        XCTFail("Expected signUp to throw for missing angler number")
      } catch {
        XCTAssert(error is AuthService.InputValidationError)
      }

  }

  func testDecodeJWTExp_malformedJWT_returnsNil() async throws {
    setAccessToken("not.a.valid.jwt", expiresInSeconds: 0)
    let auth = AuthService.shared
    let tok = await auth.currentAccessToken()
    XCTAssertNil(tok)
  }

  // --- Additional test adjustments ---
  // testSignIn_offlineFallback_withoutCachedCredentials_fails
  func testSignIn_offlineFallback_withoutCachedCredentials_fails() async {
    // Simulate no cached credentials
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    let delQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: "OfflineLastPassword"
    ]
    SecItemDelete(delQuery as CFDictionary)
    
    MockURLProtocol.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let auth = AuthService.shared
    do {
      try await auth.signIn(email: "offline@example.com", password: "offline-pass")
      XCTFail("Expected signIn to throw due to no cached credentials and network failure")
    } catch {
      if let authErr = error as? AuthService.AuthError {
        if case .networkUnavailable = authErr { XCTAssertTrue(true) } else { XCTFail("Expected networkUnavailable; got: \(authErr)") }
      } else {
        XCTFail("Expected AuthService.AuthError.networkUnavailable; got: \(error)")
      }
    }
    XCTAssertFalse(auth.isAuthenticated)
  }

  // testRememberMeOff_clearsOfflineCredsOnSignOut
  func testRememberMeOff_clearsOfflineCredsOnSignOut() async throws {
    UserDefaults.standard.set("user@example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "somepassword")

    let auth = AuthService.shared
    AuthService.shared.rememberMeEnabled = false
    await auth.signOut()

    XCTAssertNil(UserDefaults.standard.string(forKey: "OfflineLastEmail"))
    XCTAssertNil(getKeychain(account: "OfflineLastPassword"))
  }

  // testAngler_signOut_clearsOfflineCreds
  func testAngler_signOut_clearsOfflineCreds() async throws {
    UserDefaults.standard.set("angler@example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "anglerpass")

    let auth = AuthService.shared
    AuthService.shared.rememberMeEnabled = false
    await auth.signOutRemote()

    XCTAssertNil(UserDefaults.standard.string(forKey: "OfflineLastEmail"))
    XCTAssertNil(getKeychain(account: "OfflineLastPassword"))
  }

  // Replace XCTAssertEqual(err, .networkUnavailable) with pattern match example
  func testExample_networkUnavailableError() async {
    do {
      throw AuthService.AuthError.networkUnavailable
    } catch {
      if case AuthService.AuthError.networkUnavailable = error {
        XCTAssertTrue(true)
      } else {
        XCTFail("Expected networkUnavailable; got: \(error)")
      }
    }
  }
}

