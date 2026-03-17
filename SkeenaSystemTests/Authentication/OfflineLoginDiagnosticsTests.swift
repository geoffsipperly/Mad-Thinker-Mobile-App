import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class OfflineLoginDiagnosticsTests: XCTestCase {

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
    clearKeychain()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
    AuthService.resetSharedForTests()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearKeychain()
    UserDefaults.standard.removeObject(forKey: "OfflineLastEmail")
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

  // This test seeds offline credentials but uses different casing/whitespace in input
  // to replicate a likely field failure. It is expected to FAIL with current logic,
  // but will emit detailed logs to help diagnose.
  func testOfflineSignIn_emailCaseAndWhitespaceIgnored_succeeds() async throws {
    // Seed cached credentials (simulate prior successful online login)
    UserDefaults.standard.set("OfflineUser@Example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "offline-pass-123")

    // Simulate no connectivity
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    let auth = AuthService.shared

    do {
      // Intentionally provide different casing + surrounding whitespace
      try await auth.signIn(email: "  offlineuser@example.com  ", password: "offline-pass-123")
      XCTAssertTrue(auth.isAuthenticated, "Offline sign-in should succeed when only email casing/whitespace differ.")
    } catch {
      if let authErr = error as? AuthService.AuthError {
        XCTAssertEqual(authErr, .networkUnavailable)
      } else {
        XCTFail("Expected AuthService.AuthError.networkUnavailable; got: \(error)")
      }
    }
  }
  
  // New test: simulate offline-like mismatch scenario to intentionally fail, capturing logs
  func testOfflineSignIn_intentionalMismatchFailureWithLogging() async throws {
    // Seed offline credentials with specific casing and whitespace
    UserDefaults.standard.set("TestUser@Example.com", forKey: "OfflineLastEmail")
    _ = setKeychain(account: "OfflineLastPassword", value: "correct-password")

    // Simulate no connectivity
    MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

    let auth = AuthService.shared

    do {
      try await auth.signIn(email: " testuser@example.COM ", password: "wrong-password")
      XCTFail("Expected offline sign-in to fail due to password mismatch; it succeeded.")
    } catch {
      if let authErr = error as? AuthService.AuthError {
        XCTAssertEqual(authErr, .networkUnavailable, "Expected AuthService.AuthError.networkUnavailable when offline creds do not match.")
      } else {
        XCTFail("Expected AuthService.AuthError.networkUnavailable, got: \(error)")
      }
    }
  }
}

