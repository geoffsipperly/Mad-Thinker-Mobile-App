// Bend Fly Shop
// UploadAnglerContext.swift
import Foundation

enum UploadAnglerContext {
  enum UploadError: Error { case invalid, server }

  static func upload(
    anglerId: String,
    token: String,
    publicKey: String,
    species: String,
    tacticName: String,
    casting: Int,
    mobility: Int,
    gear: Int
  ) async throws {
    // Use environment-backed endpoint instead of hard-coded URL
    let url = AppEnvironment.shared.proficiencyURL

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    // Use environment anon key so it respects Dev/Test/PROD configs
    req.setValue(AppEnvironment.shared.anonKey, forHTTPHeaderField: "apikey")

    // Ensure scores are within 1..100 as required by API
    let body: [String: Any] = [
      "angler_id": anglerId,
      "species": species,
      "tactic_name": tacticName,
      "casting": max(1, min(100, casting)),
      "mobility": max(1, min(100, mobility)),
      "gear": max(1, min(100, gear))
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    // DEBUG: Log request (masked token)
    #if DEBUG
    let maskedToken: String
    if token.count > 20 {
      maskedToken = token.prefix(10) + "…" + token.suffix(5)
    } else {
      maskedToken = String(token.prefix(8)) + "…"
    }
    print("[Proficiency][REQUEST] URL: \(url.absoluteString)")
    print("[Proficiency][REQUEST] Headers: Authorization=Bearer \(maskedToken), apikey=\(AppEnvironment.shared.anonKey.prefix(8))… Content-Type=application/json")
    if let bodyData = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]),
       let bodyString = String(data: bodyData, encoding: .utf8) {
      print("[Proficiency][REQUEST] Body: \n\(bodyString)")
    }
    #endif

    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
    let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"

    #if DEBUG
    print("[Proficiency][RESPONSE] Status: \(code)")
    print("[Proficiency][RESPONSE] Body: \n\(responseBody)")
    #endif

    guard (200..<300).contains(code) else { throw UploadError.server }
  }
}
