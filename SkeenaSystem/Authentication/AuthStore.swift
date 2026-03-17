// Bend Fly Shop

import Foundation

/// Thin cache for the Supabase user access JWT so sync code (like your uploader)
/// can read it without `await`. Refresh it *before* uploads.
final class AuthStore {
  static let shared = AuthStore()
  private init() {}

  private var cachedJWT: String?

  /// Synchronous accessor used by other components (e.g., UploadCatchReportAPI).
  var jwt: String? { cachedJWT }

  /// Refresh from Supabase and cache it for synchronous use.
  @MainActor
  func refreshFromSupabase() async {
    let token = await AuthService.shared.currentAccessToken()
    self.cachedJWT = token
  }

  /// Optional: clear on logout
  func clear() { cachedJWT = nil }

  #if DEBUG
  /// Test helper: set JWT directly for testing upload flows
  func setJWTForTesting(_ token: String?) {
    cachedJWT = token
  }
  #endif
}
