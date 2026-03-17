// Bend Fly Shop
// APIURLUtilities.swift
// Shared utilities for API URL configuration

import Foundation

/// Shared utilities for building API URLs from Info.plist configuration.
enum APIURLUtilities {

  /// Reads a string value from Info.plist, trimmed of whitespace.
  /// - Parameter key: The Info.plist key to read
  /// - Returns: The trimmed string value, or empty string if not found
  static func infoPlistString(forKey key: String) -> String {
    (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// Normalizes a base URL string by ensuring it has an https:// scheme.
  /// - Parameter raw: The raw URL string (may or may not have a scheme)
  /// - Returns: The normalized URL string with scheme
  static func normalizeBaseURL(_ raw: String) -> String {
    var s = raw
    if !s.isEmpty, URL(string: s)?.scheme == nil {
      s = "https://" + s
    }
    return s
  }

  /// Reads and normalizes the API_BASE_URL from Info.plist.
  /// This is a convenience that combines `infoPlistString` and `normalizeBaseURL`.
  static var normalizedAPIBaseURL: String {
    normalizeBaseURL(infoPlistString(forKey: "API_BASE_URL"))
  }
}
