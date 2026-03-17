// Bend Fly Shop

import Foundation
@preconcurrency import LocalAuthentication

enum BiometricAuthError: Error {
  case notAvailable
  case failed
}

final class BiometricAuth {
  static let shared = BiometricAuth()
  private init() {}

  // NOTE:
  // Do NOT keep a long-lived LAContext instance. Create ephemeral contexts for
  // canEvaluatePolicy and return the evaluation context for later Keychain use.

  /// Quick boolean check for biometric capability (ephemeral context).
  var canUseBiometrics: Bool {
    var error: NSError?
    let ctx = LAContext()
    return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  // MARK: - New API (returns LAContext)

  /// Performs biometric authentication and returns the **LAContext** that satisfied
  /// the authentication. Callers *must* keep the returned LAContext alive while
  /// using it for Keychain reads (pass it into SecItemCopyMatching via
  /// kSecUseAuthenticationContext).
  ///
  /// Example:
  ///   let ctx = try await BiometricAuth.shared.authenticateContext(reason: "Sign in")
  ///   // use ctx when reading biometry-protected keychain item
  ///
  func authenticateContext(reason: String? = nil) async throws -> LAContext {
    let resolvedReason = reason ?? "Sign in to \(AppEnvironment.shared.communityName)"
    return try await withCheckedThrowingContinuation { continuation in
      let ctx = LAContext()
      // Hide fallback button ("Enter Password") for cleaner UX if desired
      ctx.localizedFallbackTitle = ""

      var authError: NSError?
      let canEval = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)

      guard canEval else {
        continuation.resume(throwing: BiometricAuthError.notAvailable)
        return
      }

      ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: resolvedReason) { success, error in
        // EvaluatePolicy callbacks are not necessarily on main thread — marshal as needed.
        DispatchQueue.main.async {
          if success {
            // Return the *same* LAContext so callers can reuse it for Keychain access.
            continuation.resume(returning: ctx)
          } else {
            continuation.resume(throwing: error ?? BiometricAuthError.failed)
          }
        }
      }
    }
  }

  // MARK: - Backwards-compatible API

  /// Backwards-compatible wrapper matching your original signature.
  /// NOTE: this discards the LAContext. Prefer authenticateContext(...) if you
  /// need to reuse the context for Keychain reads.
  @discardableResult
  func authenticate(reason: String? = nil) async throws -> Bool {
    _ = try await authenticateContext(reason: reason)
    return true
  }
}
