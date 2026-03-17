// Bend Fly Shop
// DateParsingUtilities.swift
// Shared date parsing utilities used across the codebase

import Foundation

/// Shared utilities for parsing dates from various string formats.
/// Used by LicenseTextRecognizer and FSELicense_BCFuzzyLabels.
enum DateParsingUtilities {

  /// Supported date formats for DOB parsing, in order of preference.
  private static let dobFormats = [
    "MMM d, yyyy",
    "MMM d yyyy",
    "yyyy-MM-dd",
    "yyyy/M/d",
    "M/d/yyyy",
    "MM/dd/yyyy",
    "d/M/yyyy",
    "dd/MM/yyyy"
  ]

  /// Normalizes a date-of-birth string to ISO 8601 format (yyyy-MM-dd).
  /// Handles various input formats including "Jan 15, 1990", "1990-01-15", etc.
  /// - Parameter raw: The raw date string to parse
  /// - Returns: ISO 8601 formatted date string, or nil if parsing fails
  static func normalizeDOBToISO(_ raw: String) -> String? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }

    let dfIn = DateFormatter()
    dfIn.locale = Locale(identifier: "en_US_POSIX")
    dfIn.calendar = Calendar(identifier: .gregorian)

    var date: Date?

    // Try each format in order
    for f in dobFormats {
      dfIn.dateFormat = f
      if let d = dfIn.date(from: s) {
        date = d
        break
      }
    }

    // Fallback: try to extract "MMM d, yyyy" or "MMM d yyyy" pattern via regex
    if date == nil, let m = firstMatch(in: s, pattern: #"(?i)[A-Z]{3}\s+\d{1,2},?\s+\d{4}"#, group: 0) {
      dfIn.dateFormat = m.contains(",") ? "MMM d, yyyy" : "MMM d yyyy"
      date = dfIn.date(from: m)
    }

    guard let final = date else { return nil }

    let out = DateFormatter()
    out.calendar = Calendar(identifier: .gregorian)
    out.locale = Locale(identifier: "en_US_POSIX")
    out.dateFormat = "yyyy-MM-dd"
    return out.string(from: final)
  }

  /// Extracts the first regex match from text.
  /// - Parameters:
  ///   - text: The text to search
  ///   - pattern: The regex pattern
  ///   - group: The capture group index (0 for full match)
  /// - Returns: The matched substring, or nil if no match
  static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
    guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = text as NSString
    if let m = rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
      guard group < m.numberOfRanges else { return nil }
      let r = m.range(at: group)
      if r.location != NSNotFound {
        return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }
}
