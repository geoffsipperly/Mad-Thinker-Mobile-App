import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class RoleBasedRememberMeTests: XCTestCase {

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    let d = UserDefaults.standard
    d.removeObject(forKey: "OfflineLastEmail")
    d.removeObject(forKey: "OfflineRememberMeEnabled")
    d.removeObject(forKey: "CachedFirstName")
    d.removeObject(forKey: "CachedUserType")
    d.removeObject(forKey: "CachedAnglerNumber")
    AuthService.resetSharedForTests()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    let d = UserDefaults.standard
    d.removeObject(forKey: "OfflineLastEmail")
    d.removeObject(forKey: "OfflineRememberMeEnabled")
    d.removeObject(forKey: "CachedFirstName")
    d.removeObject(forKey: "CachedUserType")
    d.removeObject(forKey: "CachedAnglerNumber")
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

  private func mockOnlineSignInAndProfile(email: String, firstName: String, userType: String) throws {
    let tokenJSON: [String: Any] = [
      "access_token": "tok-\(email)",
      "refresh_token": "ref-\(email)",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

    let userJSON: [String: Any] = [
      "id": "u-\(email)",
      "email": email,
      "user_metadata": ["first_name": firstName, "user_type": userType]
    ]
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
  }

  func testGuide_autoEnablesRememberMe_afterProfileLoad() async throws {
    let auth = AuthService.shared
    try mockOnlineSignInAndProfile(email: "guide@example.com", firstName: "G", userType: "guide")
    try await auth.signIn(email: "guide@example.com", password: "pw")
    XCTAssertEqual(auth.currentUserType, .guide)
    XCTAssertTrue(auth.rememberMeEnabled, "Remember Me should auto-enable for guides")
  }

  func testAngler_autoDisablesRememberMe_afterProfileLoad() async throws {
    let auth = AuthService.shared
    try mockOnlineSignInAndProfile(email: "angler@example.com", firstName: "A", userType: "angler")
    try await auth.signIn(email: "angler@example.com", password: "pw")
    XCTAssertEqual(auth.currentUserType, .angler)
    XCTAssertFalse(auth.rememberMeEnabled, "Remember Me should auto-disable for anglers")
  }

  func testGuide_signOut_preservesOfflineCreds() async throws {
    let auth = AuthService.shared
    try mockOnlineSignInAndProfile(email: "guide@example.com", firstName: "G", userType: "guide")
    try await auth.signIn(email: "guide@example.com", password: "pw")
    // sign out -> should preserve offline creds due to rememberMe=true
    await auth.signOut()

    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
    do {
      try await auth.signIn(email: "guide@example.com", password: "pw")
      XCTAssertTrue(auth.isAuthenticated)
    } catch {
      XCTFail("Expected offline sign-in to succeed for guide with remember me auto-enabled; error=\(error)")
    }
  }

  func testAngler_signOut_clearsOfflineCreds() async throws {
    let auth = AuthService.shared
    try mockOnlineSignInAndProfile(email: "angler@example.com", firstName: "A", userType: "angler")
    try await auth.signIn(email: "angler@example.com", password: "pw")
    // sign out -> should clear offline creds due to rememberMe=false
    await auth.signOut()

    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
    do {
      try await auth.signIn(email: "angler@example.com", password: "pw")
      XCTFail("Expected offline sign-in to fail for angler with remember me auto-disabled")
    } catch {
      if let authErr = error as? AuthService.AuthError {
        XCTAssertEqual(authErr, .networkUnavailable, "Expected networkUnavailable when offline creds are cleared for anglers.")
      } else {
        XCTFail("Expected AuthService.AuthError.networkUnavailable; got: \(error)")
      }
    }
  }
}

