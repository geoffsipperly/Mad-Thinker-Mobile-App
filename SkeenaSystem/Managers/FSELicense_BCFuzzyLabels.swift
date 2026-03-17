// Bend Fly Shop

import CoreGraphics
import Foundation
import os // Logging via AppLogging (.ocr category)

public enum FSEBCFuzzyPatches {
  // MARK: - Public entry points (safe to call from existing parser)

  /// Fuzzy "index of label" (tolerates small OCR mistakes).
  /// Example: indexOfLabelFuzzy("date of birth", in: lines)
  public static func indexOfLabelFuzzy(_ needle: String, in lines: [OCRLine], maxDistance: Int = 4) -> Int? {
    let target = norm(needle)
    var bestIdx: Int?
    var best = maxDistance + 1
    for (i, l) in lines.enumerated() {
      let cand = norm(l.text)
      let d = boundedEditDistance(between: cand, and: target, maxBound: maxDistance)
      if d <= maxDistance, d < best { best = d; bestIdx = i }
      // small boost: exact containment with punctuation noise
      if bestIdx == nil, cand.contains(tokenish(target)) { bestIdx = i }
    }
    return bestIdx
  }

  /// DOB fallback: scan the left column near Licencee/Date-of-Birth/Sex
  /// to find the first date-shaped token and return ISO "yyyy-MM-dd".
  public static func extractDOBFallback(lines: [OCRLine], leftColumnMaxX: CGFloat) -> String? {
    // 1) Anchor near Licencee or the uppercase comma-name line
    let nameAnchor = anchorIndex(for: lines, leftColumnMaxX: leftColumnMaxX)
    // 2) Build a small window around the anchor and look for a date token
    let window = windowText(around: nameAnchor, lines: lines, leftColumnMaxX: leftColumnMaxX, lookahead: 8)
    guard let token = DateParsingUtilities.firstMatch(
      in: window,
      pattern: #"(?i)\b(?:[A-Z]{3}\s+\d{1,2},?\s+\d{4}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|\d{4}[-/]\d{1,2}[-/]\d{1,2})\b"#,
      group: 0
    ) else { return nil }
    return normalizeDOBToISO(token)
  }

  /// Post-process rows: remove stray licence-like tokens from the WATER field.
  public static func cleanupClassifiedRows(_ rows: [ClassifiedLicenceParse]) -> [ClassifiedLicenceParse] {
    rows.map { r in
      var clean = r
      clean.water = cleanupWaterField(r.water)
      return clean
    }
  }

  // MARK: - Internals

  private static func anchorIndex(for lines: [OCRLine], leftColumnMaxX: CGFloat) -> Int {
    // Prefer a fuzzy "date of birth" label first
    if let i = indexOfLabelFuzzy("date of birth", in: lines) { return i }
    // Then "licencee / licensee"
    if let i = fuzzyAny(of: ["licencee", "licensee"], in: lines) { return i }
    // Then an all-caps "LAST, FIRST" name line
    if let i = lines
      .firstIndex(where: { $0.minX <= leftColumnMaxX + 0.02 && looksLikeUpperCommaName($0.text) }) { return i }
    // Fallback: first left-column line
    return lines.firstIndex(where: { $0.minX <= leftColumnMaxX + 0.02 }) ?? 0
  }

  private static func windowText(around i: Int, lines: [OCRLine], leftColumnMaxX: CGFloat, lookahead: Int) -> String {
    guard !lines.isEmpty else { return "" }
    let lo = max(0, i)
    let hi = min(lines.count - 1, i + lookahead)
    return lines[lo ... hi]
      .filter { $0.minX <= leftColumnMaxX + 0.02 }
      .map(\.text)
      .joined(separator: " ")
  }

  private static func fuzzyAny(of needles: [String], in lines: [OCRLine], maxDistance: Int = 2) -> Int? {
    for n in needles {
      if let i = indexOfLabelFuzzy(n, in: lines, maxDistance: maxDistance) { return i }
    }
    return nil
  }

  private static func looksLikeUpperCommaName(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.contains(","), t == t.uppercased() else { return false }
    // Avoid headers
    let l = t.lowercased()
    if l.contains("licence") || l.contains("license") || l.contains("angler") { return false }
    return true
  }

  // --- Water cleanup ---
  private static func cleanupWaterField(_ s: String) -> String {
    // remove embedded licence-like tokens: NAxxxxxx or NATu… etc that sneak into water
    let parts = s.split(separator: " ").map(String.init)
    let kept = parts.filter { p in
      if p.range(of: #"(?i)^(NA|NATU)[0-9A-Z]{5,}$"#, options: .regularExpression) != nil { return false }
      if p.range(of: #"(?i)^(Lic|Lic#|Vend|Vend#)$"#, options: .regularExpression) != nil { return false }
      return true
    }
    // collapse doubled spaces and stray punctuation
    return kept.joined(separator: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .replacingOccurrences(of: " ,", with: ",")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // --- DOB normalize (uses shared utility) ---
  private static func normalizeDOBToISO(_ raw: String) -> String? {
    DateParsingUtilities.normalizeDOBToISO(raw)
  }

  // MARK: - Fuzzy / normalization utilities

  private static func norm(_ s: String) -> String {
    // lowercase, trim, strip punctuation noise frequently seen in OCR (.,:;)
    let t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ":", with: " ")
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: ";", with: " ")
    // collapses → single spaces
    return t.split(separator: " ").joined(separator: " ")
  }

  private static func tokenish(_ s: String) -> String {
    s.replacingOccurrences(of: " ", with: "")
  }

  /// Bounded Levenshtein distance (stops work when bound exceeded).
  private static func boundedEditDistance(between a: String, and b: String, maxBound: Int) -> Int {
    if a == b { return 0 }
    let la = a.count, lb = b.count
    if abs(la - lb) > maxBound { return maxBound + 1 }

    let aArr = Array(a), bArr = Array(b)
    var prev = Array(0 ... lb)
    var curr = Array(repeating: 0, count: lb + 1)

    for i in 1 ... la {
      curr[0] = i
      var minInRow = curr[0]
      for j in 1 ... lb {
        let cost = (aArr[i - 1] == bArr[j - 1]) ? 0 : 1
        curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        if curr[j] < minInRow { minInRow = curr[j] }
      }
      if minInRow > maxBound { return maxBound + 1 }
      swap(&prev, &curr)
    }
    return prev[lb]
  }
}
