import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class OfflineProfileCacheTests: XCTestCase {

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "OfflineLastEmail")
    defaults.removeObject(forKey: "OfflineRememberMeEnabled")
    defaults.removeObject(forKey: "CachedFirstName")
    defaults.removeObject(forKey: "CachedUserType")
    defaults.removeObject(forKey: "CachedAnglerNumber")
    AuthService.resetSharedForTests()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "OfflineLastEmail")
    defaults.removeObject(forKey: "OfflineRememberMeEnabled")
    defaults.removeObject(forKey: "CachedFirstName")
    defaults.removeObject(forKey: "CachedUserType")
    defaults.removeObject(forKey: "CachedAnglerNumber")
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

  // Helper: set keychain value
  @discardableResult
  private func setKeychain(account: String, value: String) -> Bool {
    let del: [CFString: Any] = [ kSecClass: kSecClassGenericPassword, kSecAttrAccount: account ]
    SecItemDelete(del as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    let add: [CFString: Any] = [ kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecValueData: data ]
    let status = SecItemAdd(add as CFDictionary, nil)
    return status == errSecSuccess
  }

  private func mockOnlineSignInAndProfile(email: String, firstName: String, userType: String, anglerNumber: String? = nil) throws {
    let tokenJSON: [String: Any] = [
      "access_token": "tok-\(email)",
      "refresh_token": "ref-\(email)",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

    var userMetadata: [String: Any] = ["first_name": firstName, "user_type": userType]
    if let ang = anglerNumber { userMetadata["angler_number"] = ang }

    let userJSON: [String: Any] = [
      "id": "u-\(email)",
      "email": email,
      "user_metadata": userMetadata
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

  func testOfflineRestore_guide_showsFirstNameAndType() async throws {
    let auth = AuthService.shared
    auth.rememberMeEnabled = true

    try mockOnlineSignInAndProfile(email: "guide@example.com", firstName: "Geoff", userType: "guide")
    try await auth.signIn(email: "guide@example.com", password: "pw")

    // Sign out but keep remember me ON -> cached profile preserved
    await auth.signOut()

    // Offline attempt
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
    try await auth.signIn(email: "guide@example.com", password: "pw")

    XCTAssertTrue(auth.isAuthenticated)
    XCTAssertEqual(auth.currentFirstName, "Geoff")
    XCTAssertEqual(auth.currentUserType, .guide)
  }
}
