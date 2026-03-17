// Bend Fly Shop
// ForumAPI.swift

import Foundation

enum ForumAPIError: Error, LocalizedError {
  case invalidURL
  case requestFailed(Int)
  case requestFailedWithBody(code: Int, body: String)
  case decodingFailed
  case missingAuth

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Invalid URL."
    case let .requestFailed(code):
      "Request failed with status \(code)."
    case let .requestFailedWithBody(code, body):
      "Request failed (\(code)): \(body)"
    case .decodingFailed:
      "Failed to decode response."
    case .missingAuth:
      "You must be signed in to perform this action."
    }
  }
}

enum ForumAPI {
  // MARK: - Config (Info.plist-style composition)

  private static let rawBaseURLString = APIURLUtilities.infoPlistString(forKey: "API_BASE_URL")
  private static let baseURLString = APIURLUtilities.normalizeBaseURL(rawBaseURLString)

  private static let forumBasePath: String = {
    // Expected: "/rest/v1"
    let path = APIURLUtilities.infoPlistString(forKey: "FORUM_BASE")
    return path.isEmpty ? "/rest/v1" : path
  }()

  private static let functionsBasePath = "/functions/v1"

  private static let forumApiKey: String = {
    // In your env notes: FORUM_API_KEY = $(SUPABASE_ANON_KEY)
    // In Info.plist we can just store SUPABASE_ANON_KEY and reuse it.
    let explicit = APIURLUtilities.infoPlistString(forKey: "FORUM_API_KEY")
    if !explicit.isEmpty { return explicit }
    return APIURLUtilities.infoPlistString(forKey: "SUPABASE_ANON_KEY")
  }()

  private static func logConfig() {
    AppLogging.log("ForumAPI config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .forum)
    AppLogging.log("ForumAPI config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .forum)
    AppLogging.log("ForumAPI config — FORUM_BASE: '\(forumBasePath)'", level: .debug, category: .forum)
    AppLogging.log("ForumAPI config — FORUM_API_KEY prefix: \(forumApiKey.prefix(8))…", level: .debug, category: .forum)
  }

  /// Builds URL: https://{API_BASE_URL}{FORUM_BASE}{resourcePath} + queryItems
  private static func makeURL(resourcePath: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("ForumAPI invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .debug, category: .forum)
      throw ForumAPIError.invalidURL
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    // Normalize base.path (rare) + forumBasePath + resourcePath
    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)

    let normalizedForumBase = forumBasePath.isEmpty ? "" : (forumBasePath.hasPrefix("/") ? forumBasePath : "/" + forumBasePath)
    let normalizedForumBaseNoTrailing = normalizedForumBase.hasSuffix("/") ? String(normalizedForumBase.dropLast()) : normalizedForumBase

    let normalizedResource = resourcePath.isEmpty ? "" : (resourcePath.hasPrefix("/") ? resourcePath : "/" + resourcePath)

    comps.path = normalizedBasePath + normalizedForumBaseNoTrailing + normalizedResource

    // Preserve any query on base URL (unlikely) + passed queryItems
    let existing = base.query != nil ? (URLComponents(string: base.absoluteString)?.queryItems ?? []) : []
    let merged = existing + queryItems
    comps.queryItems = merged.isEmpty ? nil : merged

    guard let url = comps.url else {
      throw ForumAPIError.invalidURL
    }
    return url
  }

  /// Builds URL for Edge Functions: https://{API_BASE_URL}/functions/v1/{functionName}
  private static func makeFunctionURL(functionName: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("ForumAPI invalid API_BASE_URL for function — raw: '\(rawBaseURLString)'", level: .debug, category: .forum)
      throw ForumAPIError.invalidURL
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port
    comps.path = functionsBasePath + "/" + functionName
    comps.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = comps.url else {
      throw ForumAPIError.invalidURL
    }
    return url
  }

  private static func makeRequest(url: URL, method: String = "GET", accessToken: String? = nil) throws -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue(forumApiKey, forHTTPHeaderField: "apikey")
    if let token = accessToken, !token.isEmpty {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return req
  }

  private static func validateHTTP(_ resp: URLResponse, data: Data) throws {
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard (200 ..< 300).contains(code) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw ForumAPIError.requestFailedWithBody(code: code, body: body)
    }
  }

  // MARK: - Response wrappers for Edge Functions

  private struct PostsResponse: Decodable {
    let success: Bool
    let posts: [ForumPost]
  }

  private struct CreateThreadResponse: Decodable {
    let success: Bool
    let thread: ForumThread
    let post: ForumPost
  }

  private struct CreatePostResponse: Decodable {
    let success: Bool
    let post: ForumPost
  }

  // MARK: - GET

  static func fetchCategories() async throws -> [ForumCategory] {
    logConfig()
    let url = try makeURL(resourcePath: "forum_categories", queryItems: [
      URLQueryItem(name: "select", value: "*"),
      URLQueryItem(name: "order", value: "sort_order.asc")
    ])
    AppLogging.log("ForumAPI request URL (fetchCategories): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for categories
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchCategories payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchCategories raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    return try JSONDecoder().decode([ForumCategory].self, from: data)
  }

  static func fetchThreads(categoryId: String) async throws -> [ForumThread] {
    logConfig()
    let url = try makeURL(resourcePath: "forum_threads_with_authors", queryItems: [
      URLQueryItem(name: "category_id", value: "eq.\(categoryId)"),
      URLQueryItem(name: "order", value: "is_pinned.desc,created_at.desc")
    ])
    AppLogging.log("ForumAPI request URL (fetchThreads): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for threads
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchThreads payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchThreads raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    return try JSONDecoder().decode([ForumThread].self, from: data)
  }

  static func fetchPosts(threadId: String) async throws -> [ForumPost] {
    logConfig()
    let url = try makeURL(resourcePath: "forum_posts_with_authors", queryItems: [
      URLQueryItem(name: "thread_id", value: "eq.\(threadId)"),
      URLQueryItem(name: "order", value: "created_at.asc")
    ])
    AppLogging.log("ForumAPI request URL (fetchPosts): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for posts
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchPosts payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchPosts raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    return try JSONDecoder().decode([ForumPost].self, from: data)
  }

  /// Fetch posts with media attachments using Edge Function
  /// Note: Edge Function requires Authorization header even for GET requests
  static func fetchPostsWithMedia(threadId: String, accessToken: String? = nil) async throws -> [ForumPost] {
    logConfig()
    let url = try makeFunctionURL(functionName: "forum-posts", queryItems: [
      URLQueryItem(name: "threadId", value: threadId)
    ])
    AppLogging.log("ForumAPI request URL (fetchPostsWithMedia): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url, accessToken: accessToken)
    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log response
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI fetchPostsWithMedia payload =>\n\(pretty)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    let response = try JSONDecoder().decode(PostsResponse.self, from: data)
    return response.posts
  }

  /// Fetch profiles for a set of user IDs. Returns a map userId -> ForumProfile
  static func fetchProfilesMap(userIds: [String]) async throws -> [String: ForumProfile] {
    logConfig()
    let ids = Array(Set(userIds)).filter { !$0.isEmpty }
    guard !ids.isEmpty else { return [:] }

    // Build id=in.(uuid1,uuid2,...)
    let inList = "in.(\(ids.joined(separator: ",")))"

    let url = try makeURL(resourcePath: "profiles", queryItems: [
      URLQueryItem(name: "select", value: "id,first_name,last_name,user_type"),
      URLQueryItem(name: "id", value: inList)
    ])
    AppLogging.log("ForumAPI request URL (fetchProfilesMap): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)
    try validateHTTP(resp, data: data)

    let arr = try JSONDecoder().decode([ForumProfile].self, from: data)
    var dict: [String: ForumProfile] = [:]
    for p in arr { dict[p.id] = p }
    return dict
  }

  // MARK: - POST / PATCH / DELETE (auth required)

  /// Create a new thread with initial post and optional media attachments
  static func createThreadWithMedia(
    accessToken: String,
    categoryId: String,
    title: String,
    content: String,
    media: [MediaAttachment]? = nil
  ) async throws -> (thread: ForumThread, post: ForumPost) {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    let url = try makeFunctionURL(functionName: "forum-posts", queryItems: [
      URLQueryItem(name: "action", value: "thread")
    ])
    AppLogging.log("ForumAPI request URL (createThreadWithMedia): \(url.absoluteString)", level: .debug, category: .forum)

    var req = try makeRequest(url: url, method: "POST", accessToken: accessToken)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "categoryId": categoryId,
      "title": title,
      "content": content
    ]
    if let media = media, !media.isEmpty {
      body["media"] = media.map { [
        "fileName": $0.fileName,
        "mimeType": $0.mimeType,
        "data_base64": $0.data_base64
      ] 
      }
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log response
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI createThreadWithMedia payload =>\n\(pretty)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    let response = try JSONDecoder().decode(CreateThreadResponse.self, from: data)
    return (response.thread, response.post)
  }

  /// Legacy method for backward compatibility (no media)
  static func createThread(
    accessToken: String,
    categoryId: String,
    userId: String,
    title: String
  ) async throws -> ForumThread {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    let url = try makeURL(resourcePath: "forum_threads")
    AppLogging.log("ForumAPI request URL (createThread): \(url.absoluteString)", level: .debug, category: .forum)

    var req = try makeRequest(url: url, method: "POST", accessToken: accessToken)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("return=representation", forHTTPHeaderField: "Prefer")

    let body: [String: Any] = [
      "category_id": categoryId,
      "user_id": userId,
      "title": title
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for createThread
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI createThread payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI createThread raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)

    let threads = try JSONDecoder().decode([ForumThread].self, from: data)
    guard let first = threads.first else { throw ForumAPIError.decodingFailed }
    return first
  }

  /// Create a post/reply with optional media attachments using Edge Function
  static func createPostWithMedia(
    accessToken: String,
    threadId: String,
    content: String,
    media: [MediaAttachment]? = nil
  ) async throws -> ForumPost {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    let url = try makeFunctionURL(functionName: "forum-posts")
    AppLogging.log("ForumAPI request URL (createPostWithMedia): \(url.absoluteString)", level: .debug, category: .forum)

    var req = try makeRequest(url: url, method: "POST", accessToken: accessToken)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "threadId": threadId,
      "content": content
    ]
    if let media = media, !media.isEmpty {
      body["media"] = media.map { [
        "fileName": $0.fileName,
        "mimeType": $0.mimeType,
        "data_base64": $0.data_base64
      ] 
      }
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log response
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI createPostWithMedia payload =>\n\(pretty)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)
    let response = try JSONDecoder().decode(CreatePostResponse.self, from: data)
    return response.post
  }

  /// Legacy method for backward compatibility (no media)
  static func createPost(
    accessToken: String,
    threadId: String,
    userId: String,
    content: String
  ) async throws -> ForumPost {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    let url = try makeURL(resourcePath: "forum_posts")
    AppLogging.log("ForumAPI request URL (createPost): \(url.absoluteString)", level: .debug, category: .forum)

    var req = try makeRequest(url: url, method: "POST", accessToken: accessToken)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("return=representation", forHTTPHeaderField: "Prefer")

    let body: [String: Any] = [
      "thread_id": threadId,
      "user_id": userId,
      "content": content
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for createPost
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI createPost payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI createPost raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    try validateHTTP(resp, data: data)

    let posts = try JSONDecoder().decode([ForumPost].self, from: data)
    guard let first = posts.first else { throw ForumAPIError.decodingFailed }
    return first
  }

  static func updatePost(accessToken: String, postId: String, content: String) async throws {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    // PATCH with filter as query item: ?id=eq.{postId}
    let url = try makeURL(resourcePath: "forum_posts", queryItems: [
      URLQueryItem(name: "id", value: "eq.\(postId)")
    ])
    AppLogging.log("ForumAPI request URL (updatePost): \(url.absoluteString)", level: .debug, category: .forum)

    var req = try makeRequest(url: url, method: "PATCH", accessToken: accessToken)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "content": content,
      "is_edited": true
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for updatePost
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI updatePost payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI updatePost raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard (200 ..< 300).contains(code) else {
      // keep old behavior for update/delete errors
      throw ForumAPIError.requestFailed(code)
    }
  }

  static func deletePost(accessToken: String, postId: String) async throws {
    guard !accessToken.isEmpty else { throw ForumAPIError.missingAuth }

    logConfig()
    // DELETE with filter as query item: ?id=eq.{postId}
    let url = try makeURL(resourcePath: "forum_posts", queryItems: [
      URLQueryItem(name: "id", value: "eq.\(postId)")
    ])
    AppLogging.log("ForumAPI request URL (deletePost): \(url.absoluteString)", level: .debug, category: .forum)

    let req = try makeRequest(url: url, method: "DELETE", accessToken: accessToken)

    let (data, resp) = try await URLSession.shared.data(for: req)

    // Debug: log full response payload for deletePost
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let pretty = String(data: prettyData, encoding: .utf8) {
      AppLogging.log("ForumAPI deletePost payload =>\n\(pretty)", level: .debug, category: .forum)
    } else if let raw = String(data: data, encoding: .utf8) {
      AppLogging.log("ForumAPI deletePost raw payload =>\n\(raw)", level: .debug, category: .forum)
    }

    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard (200 ..< 300).contains(code) else {
      // keep old behavior for update/delete errors
      // (still include body in logs for debugging)
      let body = String(data: data, encoding: .utf8) ?? ""
      if !body.isEmpty {
        AppLogging.log("ForumAPI deletePost failed body: \(body)", level: .debug, category: .forum)
      }
      throw ForumAPIError.requestFailed(code)
    }
  }
}
