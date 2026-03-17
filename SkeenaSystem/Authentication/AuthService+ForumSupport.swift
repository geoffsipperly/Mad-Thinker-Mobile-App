// Bend Fly Shop

// AuthService+ForumSupport.swift
import Foundation

extension AuthService {
  /// Returns a fresh access token if needed (calls your refresh logic under the hood).
  func forumAccessToken() async -> String? {
    await currentAccessToken()
  }

  /// Extracts the Supabase user id (UUID) from a JWT access token's `sub` claim.
  func userId(fromAccessToken token: String) -> String? {
    // Decode JWT payload (base64url)
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var b64 = parts[1]
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 {
      b64.append("=")
    }
    guard
      let data = Data(base64Encoded: b64),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj["sub"] as? String
  }
}
