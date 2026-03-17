import XCTest
import LocalAuthentication
@testable import SkeenaSystem

/// Tests for BiometricAuth functionality.
/// Note: Actual biometric authentication cannot be tested in unit tests
/// as it requires hardware interaction. These tests verify the API contracts
/// and error handling behavior.
@MainActor
final class BiometricAuthTests: XCTestCase {

  // MARK: - Singleton Tests

  func testSharedInstance_isSingleton() {
    let instance1 = BiometricAuth.shared
    let instance2 = BiometricAuth.shared
    XCTAssertTrue(instance1 === instance2, "BiometricAuth.shared should return the same instance")
  }

  // MARK: - canUseBiometrics Tests

  func testCanUseBiometrics_returnsBoolean() {
    // This test verifies the property exists and returns a boolean
    // The actual value depends on the simulator/device capabilities
    let result = BiometricAuth.shared.canUseBiometrics
    XCTAssertNotNil(result, "canUseBiometrics should return a non-nil boolean")
    // On simulator, this will typically be false
    XCTAssertFalse(result, "canUseBiometrics should be false on simulator")
  }

  // MARK: - BiometricAuthError Tests

  func testBiometricAuthError_notAvailable_exists() {
    let error = BiometricAuthError.notAvailable
    XCTAssertNotNil(error)
  }

  func testBiometricAuthError_failed_exists() {
    let error = BiometricAuthError.failed
    XCTAssertNotNil(error)
  }

  // MARK: - authenticateContext Tests

  func testAuthenticateContext_throwsNotAvailable_whenBiometricsUnavailable() async {
    // On simulator without biometrics, this should throw notAvailable
    do {
      _ = try await BiometricAuth.shared.authenticateContext(reason: "Test")
      XCTFail("Expected authenticateContext to throw on simulator")
    } catch let error as BiometricAuthError {
      XCTAssertEqual(error, .notAvailable, "Should throw notAvailable on simulator")
    } catch {
      XCTFail("Expected BiometricAuthError.notAvailable, got: \(error)")
    }
  }

  // MARK: - authenticate (backwards-compatible) Tests

  func testAuthenticate_throwsNotAvailable_whenBiometricsUnavailable() async {
    // On simulator without biometrics, this should throw notAvailable
    do {
      _ = try await BiometricAuth.shared.authenticate(reason: "Test")
      XCTFail("Expected authenticate to throw on simulator")
    } catch let error as BiometricAuthError {
      XCTAssertEqual(error, .notAvailable, "Should throw notAvailable on simulator")
    } catch {
      XCTFail("Expected BiometricAuthError.notAvailable, got: \(error)")
    }
  }

  // MARK: - LAContext Configuration Tests

  func testLAContext_interactionNotAllowed_canBeSet() {
    // Verify the API we use for the deprecation fix works correctly
    let ctx = LAContext()
    ctx.interactionNotAllowed = true
    XCTAssertTrue(ctx.interactionNotAllowed, "interactionNotAllowed should be settable to true")

    ctx.interactionNotAllowed = false
    XCTAssertFalse(ctx.interactionNotAllowed, "interactionNotAllowed should be settable to false")
  }
}
