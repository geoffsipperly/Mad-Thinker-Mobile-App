import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class OfflineRememberMeTests: XCTestCase {

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    UserDefaults.standard.removeObject(forKey: "OfflineRememberMeEnabled")
    AuthService.resetSharedForTests()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    UserDefaults.standard.removeObject(forKey: "OfflineRememberMeEnabled")
    super.tearDown()
  }

  private func clearKeychain() {
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
    let del: [CFString: Any] = [ kSecClass: kSecClassGenericPassword, kSecAttrAccount: account ]
    SecItemDelete(del as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    let add: [CFString: Any] = [ kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecValueData: data ]
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
    if status == errSecSuccess, let d = res as? Data, let s = String(data: d, encoding: .utf8) {
      return s
    }
    return nil
  }

  // Helper: mock a successful sign-in sequence
  private func mockOnlineSignIn(access: String = "tok", refresh: String = "ref", email: String = "user@example.com") throws -> (Data, Data) {
    let tokenJSON: [String: Any] = [
      "access_token": access, "refresh_token": refresh, "expires_in": 3600, "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)
    let userJSON: [String: Any] = ["id": "u1", "email": email]
    let userData = try JSONSerialization.data(withJSONObject: userJSON)
    MockURLProtocol.requestHandler = { req in
      guard let url = req.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }
    return (tokenData, userData)
  }

  func testRememberMeOn_preservesOfflineCredsAcrossSignOut() async throws {
    // Enable remember me
    AuthService.shared.rememberMeEnabled = true

    // Online sign-in
    _ = try mockOnlineSignIn(email: "remember@example.com")
    try await AuthService.shared.signIn(email: "remember@example.com", password: "pw123456")

    // Verify offline creds were recorded after online sign-in
    let cachedEmail = UserDefaults.standard.string(forKey: "OfflineLastEmail") ?? "<nil>"
    let cachedPwLen = (getKeychain(account: "OfflineLastPassword") ?? "").count
    XCTAssertEqual(cachedEmail, "remember@example.com", "Email should be cached after online sign-in when Remember Me is ON")
    XCTAssertGreaterThan(cachedPwLen, 0, "Offline password should be cached when Remember Me is ON")

    // Sign out (should preserve offline creds)
    await AuthService.shared.signOut()

    // Verify offline creds were preserved after sign-out
    let cachedPwLenAfterSignOut = (getKeychain(account: "OfflineLastPassword") ?? "").count
    XCTAssertGreaterThan(cachedPwLenAfterSignOut, 0, "Offline password should be preserved after sign-out when Remember Me is ON")

    // Simulate offline
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    // Attempt offline sign-in with same creds
    do {
      try await AuthService.shared.signIn(email: "remember@example.com", password: "pw123456")
      XCTAssertTrue(AuthService.shared.isAuthenticated)
    } catch {
      XCTFail("Expected offline sign-in to succeed with remember me ON; error=\(error)")
    }
  }

  func testRememberMeOff_clearsOfflineCredsOnSignOut() async throws {
    // Disable remember me
    AuthService.shared.rememberMeEnabled = false

    // Online sign-in
    _ = try mockOnlineSignIn(email: "noremember@example.com")
    try await AuthService.shared.signIn(email: "noremember@example.com", password: "pw654321")

    // Sign out (should clear offline creds)
    await AuthService.shared.signOut()

    // Simulate offline
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    // Attempt offline sign-in with same creds -> expect failure
    do {
      try await AuthService.shared.signIn(email: "noremember@example.com", password: "pw654321")
      XCTFail("Expected offline sign-in to fail with remember me OFF")
    } catch {
        if let authErr = error as? AuthService.AuthError {
          XCTAssertEqual(authErr, .networkUnavailable)
        } else {
          XCTFail("Expected AuthService.AuthError.networkUnavailable; got: \(error)")
        }
    }
  }
}

