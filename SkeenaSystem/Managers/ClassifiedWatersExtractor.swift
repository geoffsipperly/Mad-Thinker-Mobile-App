// Bend Fly Shop

import CoreGraphics
import Foundation

public enum BCClassifiedWaters {
  public static func parse(lines: [OCRLine]) -> [ClassifiedLicenceParse] {
    // 1) Find header line index and Y
    guard let headerIdx = lines.firstIndex(where: { l in
      let t = l.text.lowercased()
      return t.contains("classified waters licence")
        || t.contains("classified waters license")
        || t.contains("classified waters licences")
    }) else {
      AppLogging.log("OCR: Classified header NOT found", level: .debug, category: .ocr)
      return []
    }
    let headerY = lines[headerIdx].midY
    AppLogging.log({ "OCR header found at index: \(headerIdx)" }, level: .debug, category: .ocr)

    // 2) Candidate row seeds: NA + digits below header
      let licRE = try? NSRegularExpression(pattern: #"(?i)\b(?:N\s*A|NA|C\s*A|CA)\s*\d{6,}\b"#)
      let naRE  = try? NSRegularExpression(pattern: #"(?i)\b(?:NA|CA)\d{6,}\b"#)
      let dateRE = try? NSRegularExpression(pattern: #"(?i)\b\d{1,2}\s+[A-Z]{3}\s+\d{1,4}\b"#)

    let seeds: [OCRLine] = lines.filter { l in
      guard l.midY < headerY else { return false }
      let ns = l.text as NSString
      return licRE?.firstMatch(in: l.text, range: NSRange(location: 0, length: ns.length)) != nil
    }.sorted { $0.midY > $1.midY } // top→bottom

    if seeds.isEmpty {
      AppLogging.log("OCR: No licence-id rows found", level: .debug, category: .ocr)
      return []
    }

    // 3) Parse each row using fragment-level logic on the same Y band
    let yTol: CGFloat = 0.0090 // tight to avoid cross-row bleed
    var rows: [ClassifiedLicenceParse] = []
    let df = bcDateFormatter()

    for seed in seeds {
      guard let seedLic = extractLic(fromSeedText: seed.text) else { continue }

      // Collect same-row fragments with geometry
      struct Frag { let text: String; let norm: String; let minX: CGFloat; let midY: CGFloat }
      let frags: [Frag] = lines
        .filter { abs($0.midY - seed.midY) <= yTol }
        .sorted { $0.minX < $1.minX }
        .map { Frag(
          text: $0.text,
          norm: normalizeRow($0.text),
          minX: $0.minX,
          midY: $0.midY
        ) 
        }

      // Locate the fragment that contains the *seed* licence
      guard let seedIdx = frags.firstIndex(where: { f in
        f.norm.range(of: seedLic, options: .regularExpression) != nil
      }) else {
        AppLogging.log("seed licence not found among fragments", level: .debug, category: .ocr)
        continue
      }

      // Scan fragments to the right for the first two dates
      var dateStrings: [String] = []
      var firstDateFragIndex: Int?
      for (idx, f) in frags.enumerated() where idx > seedIdx {
        // normalize tight "15OCT" -> "15 OCT"
        let norm = f.norm
          .replacingOccurrences(of: #"(?i)\b(\d{1,2})([A-Z]{3})\b"#, with: "$1 $2", options: .regularExpression)

        let ns = norm as NSString
        let matches = dateRE?.matches(in: norm, range: NSRange(location: 0, length: ns.length)) ?? []
        if !matches.isEmpty {
          if firstDateFragIndex == nil { firstDateFragIndex = idx }
          for m in matches {
            if let r = Range(m.range, in: norm) {
              dateStrings.append(String(norm[r]))
              if dateStrings.count == 2 { break }
            }
          }
        }
        if dateStrings.count == 2 { break }
      }

      guard dateStrings.count == 2, let firstIdx = firstDateFragIndex else {
        AppLogging.log({ "Row@Y=\(String(format: "%.4f", seed.midY)) -> insufficient dates" }, level: .debug, category: .ocr)
        continue
      }

      // ---- WATER EXTRACTION (seed-fragment suffix + intervening fragments) ----

        // Use normalized fragment to extract suffix after seedLic (works for NA or CA)
        let seedNorm = frags[seedIdx].norm // already normalized/uppercased
        var seedSuffix = ""
        if let r = seedNorm.range(of: seedLic, options: .regularExpression) {
          seedSuffix = String(seedNorm[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

      // 3b) Intervening fragments strictly between seed and first-date fragment,
      //     skipping any fragment that looks like another NA######
      let between = frags[(seedIdx + 1) ..< firstIdx]
        .filter { f in
          let ns = f.norm as NSString
          return naRE?.firstMatch(in: f.norm, range: NSRange(location: 0, length: ns.length)) == nil
        }
        .map { $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        .joined(separator: " ")

      var waterRaw = [seedSuffix, between]
        .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // 3c) Fallback: slice a joined-string window from seed-lic end to first-date start,
        //     then cut at any intervening NA###### or CA###### if present.
        if waterRaw.isEmpty {
          let joined = frags.map { $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .joined(separator: " ")
          let joinedNorm = normalizeRow(joined)

          if let licR = joinedNorm.range(of: seedLic, options: .regularExpression) {
            let afterLic = joinedNorm[licR.upperBound...] // Substring

            // SEARCH IN `afterLic` DIRECTLY so returned Range indices belong to `afterLic`
            if let firstDateR = afterLic.range(of: dateStrings[0], options: .caseInsensitive) {
              var betweenNorm = String(afterLic[..<firstDateR.lowerBound])

              // Accept NA or CA tokens as the next license marker
              if let nextNA = betweenNorm.range(of: #"\b(?:NA|CA)\d{6,}\b"#, options: .regularExpression) {
                betweenNorm = String(betweenNorm[..<nextNA.lowerBound])
              }

              waterRaw = betweenNorm
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
          }
        }

      guard !waterRaw.isEmpty else {
        AppLogging.log("empty water segment", level: .debug, category: .ocr)
        continue
      }

      var water = ocrFixWater(waterRaw.capitalized)
      water = ocrFixCommon(water)

      let fromS = dateStrings[0]
      let toS = dateStrings[1]
      let fromD = parseBCDate(fromS, df: df)
      let toD = parseBCDate(toS, df: df)

      AppLogging.log({ "Row@Y=\(String(format: "%.4f", seed.midY)) -> LIC: \(seedLic) | WATER: \(water) | FROM: \(fromS) | TO: \(toS)" }, level: .debug, category: .ocr)

      rows.append(ClassifiedLicenceParse(
        licNumber: seedLic,
        water: water,
        validFrom: fromD,
        validTo: toD,
        guideName: "",
        vendor: ""
      ))
    }

    // De-dup
    var seen = Set<String>()
    rows = rows.filter { r in
      let key = "\(r.licNumber.uppercased())|\(r.water.uppercased())|\(r.validFrom?.timeIntervalSince1970 ?? -1)|\(r.validTo?.timeIntervalSince1970 ?? -1)"
      return seen.insert(key).inserted
    }

    AppLogging.log({ "OCR parsed rows: \(rows.count)" }, level: .info, category: .ocr)
    return rows
  }

  // MARK: - Local helpers

    fileprivate static func extractLic(fromSeedText raw: String) -> String? {
      let norm = normalizeRow(raw)
      if let r = norm.range(of: #"\b(?:NA|CA)\d{6,}\b"#, options: .regularExpression) {
        return String(norm[r])
      }
      return nil
    }

  fileprivate static func normalizeRow(_ s: String) -> String {
      s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)\bN\s*A\s*(?=\d)"#, with: "NA", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)\bC\s*A\s*(?=\d)"#, with: "CA", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        .uppercased()
  }

  fileprivate static func ocrFixWater(_ s: String) -> String {
    var x = s
    x = x.replacingOccurrences(of: "Nehaiem", with: "Nehalem")
    x = x.replacingOccurrences(of: "Nestueca", with: "Nestucca")
    return x.trimmingCharacters(in: CharacterSet.whitespaces)
  }

  fileprivate static func ocrFixCommon(_ s: String) -> String {
    var x = s
    x = x.replacingOccurrences(of: "Adut", with: "Adult")
    x = x.replacingOccurrences(of: "Chinock", with: "Chinook")
    x = x.replacingOccurrences(of: "ChinocK", with: "Chinook")
    x = x.replacingOccurrences(of: "DEREKB.", with: "DEREK B")
    x = x.replacingOccurrences(of: "DEREK B..", with: "DEREK B")
    return x.trimmingCharacters(in: CharacterSet.whitespaces)
  }

  fileprivate static func bcDateFormatter() -> DateFormatter {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "dd MMM yyyy"
    return df
  }

  fileprivate static func parseBCDate(_ s: String, df: DateFormatter) -> Date? {
    if let d = df.date(from: s) { return d }
    let fixed = s.replacingOccurrences(
      of: #"^\s*(\d{1})\s"#,
      with: "0$1 ",
      options: .regularExpression
    )
    return df.date(from: fixed)
  }
}

// MARK: - Small Range helper

private extension Range where Bound == String.Index {
  func clamped(to prefix: String) -> Range<String.Index>? {
    guard let start = lowerBound.samePosition(in: prefix),
          let end = upperBound.samePosition(in: prefix) else { return nil }
    return start ..< end
  }
}
