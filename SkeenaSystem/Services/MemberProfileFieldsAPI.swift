// Bend Fly Shop
// MemberProfileFieldsAPI.swift
//
// Shared URL composition for the member-profile-fields edge function.
// Used by GearChecklist, AnglerAboutYou (proficiency), and ManagePreferencesView.
//
// URL composition:
//   API_BASE_URL + MEMBER_PROFILE_FIELDS_URL (both from Info.plist)

import Foundation

enum MemberProfileFieldsAPI {
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

  private static let fieldsPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "MEMBER_PROFILE_FIELDS_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    ?? "/functions/v1/member-profile-fields"
  }()

  /// GET URL with community_id and category query params.
  static func url(communityId: String, category: String) throws -> URL {
    guard let base = URL(string: baseURLString),
          let scheme = base.scheme,
          let host = base.host
    else { throw URLError(.badURL) }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = fieldsPath.hasPrefix("/") ? fieldsPath : "/" + fieldsPath
    comps.path = normalizedBasePath + normalizedPath

    comps.queryItems = [
      URLQueryItem(name: "community_id", value: communityId),
      URLQueryItem(name: "category", value: category)
    ]

    guard let url = comps.url else { throw URLError(.badURL) }
    return url
  }

  /// POST URL (no query params).
  static func postURL() throws -> URL {
    guard let base = URL(string: baseURLString),
          let scheme = base.scheme,
          let host = base.host
    else { throw URLError(.badURL) }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = fieldsPath.hasPrefix("/") ? fieldsPath : "/" + fieldsPath
    comps.path = normalizedBasePath + normalizedPath

    guard let url = comps.url else { throw URLError(.badURL) }
    return url
  }
}
