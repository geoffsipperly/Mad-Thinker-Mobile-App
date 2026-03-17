// Bend Fly Shop
// CatchStoryService.swift
//
// Drop-in refactor:
// - Composes endpoint URL using your convention:
//     API_BASE_URL + CATCH_STORY_URL
//   (both read from Info.plist, with safe normalization)
//
// Info.plist required keys:
//   API_BASE_URL     e.g. "your-project.supabase.co" OR "https://your-project.supabase.co"
//   CATCH_STORY_URL  e.g. "/functions/v1/catch-story"  (recommended; must be a relative path)
//
// Notes:
// - Keeps your retry-on-auth-error behavior (400/401/403).
// - Keeps headers consistent with your other services (Accept, Authorization, apikey, Content-Type).
// - Keeps UserDefaults caching behavior unchanged.

import Foundation

// MARK: - DTO + Errors

// Now Codable so we can persist to UserDefaults easily
struct CatchStoryDTO: Codable {
  let catch_id: String
  let title: String
  let summary: String
}

enum CatchStoryError: Error, LocalizedError {
  case notAuthenticated
  case badStatus(Int, String?)
  case decoding(Error)
  case network(Error)
  case badURL

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      "You are not signed in."
    case let .badStatus(code, message):
      "Request failed (\(code))\(message.flatMap { ": \($0)" } ?? "")."
    case let .decoding(err):
      "Failed to read server response: \(err.localizedDescription)"
    case let .network(err):
      "Network error: \(err.localizedDescription)"
    case .badURL:
      "Unsupported URL (check API_BASE_URL / CATCH_STORY_URL)."
    }
  }
}

// MARK: - URL Composition Helper (Convention)

enum CatchStoryAPI {
  private static let rawBaseURLString: String = {
    (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }()

  private static let baseURLString: String = {
    var s = rawBaseURLString
    if !s.isEmpty, URL(string: s)?.scheme == nil {
      s = "https://" + s
    }
    return s
  }()

  private static let storyPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "CATCH_STORY_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    ?? "/functions/v1/catch-story"
  }()

  static func url() throws -> URL {
    guard let base = URL(string: baseURLString),
          let scheme = base.scheme,
          let host = base.host
    else { throw CatchStoryError.badURL }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    // allow API_BASE_URL to include an optional base path
    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)

    let normalizedPath = storyPath.hasPrefix("/") ? storyPath : "/" + storyPath
    comps.path = normalizedBasePath + normalizedPath

    // preserve any query items already present in API_BASE_URL (rare, but safe)
    let existing = base.query != nil
      ? (URLComponents(string: base.absoluteString)?.queryItems ?? [])
      : []
    comps.queryItems = existing.isEmpty ? nil : existing

    guard let url = comps.url else { throw CatchStoryError.badURL }
    return url
  }
}

// MARK: - Service

final class CatchStoryService {
  static let shared = CatchStoryService()
  private init() {}

  // Existing API: fetch from server (keeps existing retry behavior).
  func fetchStory(catchId: String) async throws -> CatchStoryDTO {
    try await fetchStoryInternal(catchId: catchId, allowRetryOnAuthError: true)
  }

  // New: try cache first, otherwise fetch and persist
  func fetchStoryWithCache(catchId: String) async throws -> CatchStoryDTO {
    let auth = AuthService.shared
    var userId: String?
    if let token = await auth.currentAccessToken() {
      userId = auth.userId(fromAccessToken: token)
    }

    if let cached = loadFromCache(catchId: catchId, userId: userId) {
      return cached
    }

    // No local cache: request from server and persist
    let fetched = try await fetchStory(catchId: catchId)
    saveToCache(fetched, userId: userId)
    return fetched
  }

  // New: always fetch fresh from server and update local cache
  func fetchFreshStory(catchId: String) async throws -> CatchStoryDTO {
    let auth = AuthService.shared
    var userId: String?
    if let token = await auth.currentAccessToken() {
      userId = auth.userId(fromAccessToken: token)
    }

    let fresh = try await fetchStoryInternal(catchId: catchId, allowRetryOnAuthError: true)
    saveToCache(fresh, userId: userId)
    return fresh
  }

  // Optional: clear cached story for this catch (useful for tests / debug)
  func clearCachedStory(catchId: String) {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: cacheKey(catchId: catchId, userId: nil))
  }

  // MARK: - Internal networking

  // Mirrors AnglerLandingView's retry logic for 400/401/403
  private func fetchStoryInternal(catchId: String, allowRetryOnAuthError: Bool) async throws -> CatchStoryDTO {
    let auth = AuthService.shared
    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      throw CatchStoryError.notAuthenticated
    }

    let url: URL
    do {
      url = try CatchStoryAPI.url()
    } catch {
      throw CatchStoryError.badURL
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"

    // Match landing view headers exactly (+ Content-Type for POST)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    req.httpBody = try JSONSerialization.data(withJSONObject: ["catch_id": catchId], options: [])

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      guard (200 ..< 300).contains(code) else {
        // If auth-related and we can retry, refresh token and retry once
        if allowRetryOnAuthError, [400, 401, 403].contains(code) {
          _ = await auth.currentAccessToken() // refresh under the hood
          return try await fetchStoryInternal(catchId: catchId, allowRetryOnAuthError: false)
        }
        let message = String(data: data, encoding: .utf8)
        throw CatchStoryError.badStatus(code, message)
      }

      do {
        return try JSONDecoder().decode(CatchStoryDTO.self, from: data)
      } catch {
        throw CatchStoryError.decoding(error)
      }
    } catch {
      throw CatchStoryError.network(error)
    }
  }

  // MARK: - Local cache (UserDefaults)

  private func cacheKey(catchId: String, userId: String?) -> String {
    if let u = userId, !u.isEmpty {
      return "epicwaters.catchstory.\(u).\(catchId)"
    } else {
      return "epicwaters.catchstory.anon.\(catchId)"
    }
  }

  private func loadFromCache(catchId: String, userId: String?) -> CatchStoryDTO? {
    let key = cacheKey(catchId: catchId, userId: userId)
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: key) else { return nil }
    do {
      return try JSONDecoder().decode(CatchStoryDTO.self, from: data)
    } catch {
      defaults.removeObject(forKey: key)
      return nil
    }
  }

  private func saveToCache(_ story: CatchStoryDTO, userId: String?) {
    let key = cacheKey(catchId: story.catch_id, userId: userId)
    do {
      let data = try JSONEncoder().encode(story)
      UserDefaults.standard.set(data, forKey: key)
    } catch {
      // ignore cache failures for now; network result still returned
      print("[CatchStoryService] failed to cache story: \(error)")
    }
  }
}
