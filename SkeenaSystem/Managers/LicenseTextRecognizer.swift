// Bend Fly Shop

import Foundation
import UIKit
import Vision
import os // Logging via AppLogging (.ocr category)

// ===== Debugging =====

@inline(__always)
private func fmt(_ r: CGRect) -> String {
  String(format: "(x:%.4f y:%.4f w:%.4f h:%.4f)", r.origin.x, r.origin.y, r.size.width, r.size.height)
}

// MARK: - Result types

public struct ClassifiedLicenceParse: Hashable {
  public var licNumber: String
  public var water: String
  public var validFrom: Date?
  public var validTo: Date?
  public var guideName: String // kept for compatibility (unused → "")
  public var vendor: String // kept for compatibility (unused → "")
}

public struct FSELicenseScanResult {
  public let fullText: String
  public let name: String?
  public let licenseNumber: String?
  public let classifiedLicences: [ClassifiedLicenceParse]

  // Only the fields we’re standardizing on
  public let dobISO8601: String? // "yyyy-MM-dd"
  public let telephone: String? // normalized
  public let residency: String? // "B.C. Resident" | "NOT A CANADIAN RESIDENT"
}

// MARK: - Shared OCR line model (visible to helper file)

public struct OCRLine {
  public let text: String
  public let bbox: CGRect // normalized; origin = bottom-left
  public let confidence: Float
  public var midY: CGFloat { bbox.midY }
  public var minX: CGFloat { bbox.minX }
  public var maxX: CGFloat { bbox.maxX }
  public init(text: String, bbox: CGRect, confidence: Float) {
    self.text = text; self.bbox = bbox; self.confidence = confidence
  }
}

// MARK: - Entry point

public enum FSELicenseTextRecognizer {
  public enum Region: Equatable { case auto, bcNonTidal }

  public struct Options {
    public var recognitionLanguages: [String] = ["en-CA", "en-US"]
    public var region: Region = .auto
    public init(
      recognitionLanguages: [String] = ["en-CA", "en-US"],
      region: Region = .auto
    ) {
      self.recognitionLanguages = recognitionLanguages
      self.region = region
    }
  }

  public static func recognize(
    in image: UIImage,
    options: Options = Options(),
    completion: @escaping (FSELicenseScanResult) -> Void
  ) {
    guard let cg = image.cgImage else {
      completion(FSELicenseScanResult(
        fullText: "",
        name: nil,
        licenseNumber: nil,
        classifiedLicences: [],
        dobISO8601: nil,
        telephone: nil,
        residency: nil
      ))
      return
    }

    let request = VNRecognizeTextRequest { request, _ in
      let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
      let lines: [OCRLine] = obs.compactMap { o in
        guard let top = o.topCandidates(1).first else { return nil }
        return OCRLine(text: top.string, bbox: o.boundingBox, confidence: top.confidence)
      }

      // Sort top-to-bottom (Vision bbox origin = bottom-left)
      let linesTB = lines.sorted(by: { $0.bbox.maxY > $1.bbox.maxY })
      let full = linesTB.map(\.text).joined(separator: "\n")

      AppLogging.log({ "OCR total lines: \n\(linesTB.count)" }, level: .debug, category: .ocr)
      for (i, l) in linesTB.enumerated() {
        AppLogging.log({ String(format: " [%03d] x=%.3f..%.3f ymid=%.3f | %@", i, l.minX, l.maxX, l.midY, l.text) }, level: .debug, category: .ocr)
      }

      let useBC = options.region == .bcNonTidal || isBCNonTidal(fullText: full)
      if useBC, let bc = parseBCNonTidal(fullText: full, lines: linesTB) {
        DispatchQueue.main.async {
          completion(FSELicenseScanResult(
            fullText: full,
            name: bc.name,
            licenseNumber: bc.license,
            classifiedLicences: bc.rows,
            dobISO8601: bc.dobISO8601,
            telephone: bc.telephone,
            residency: bc.residency
          ))
        }
        return
      }

      // Generic fallback (no table)
      let generic = parseGeneric(fullText: full, lines: linesTB)
      DispatchQueue.main.async {
        completion(FSELicenseScanResult(
          fullText: full,
          name: generic.name,
          licenseNumber: generic.license,
          classifiedLicences: [],
          dobISO8601: generic.dobISO8601,
          telephone: generic.telephone,
          residency: generic.residency
        ))
      }
    }

    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = options.recognitionLanguages

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do { try handler.perform([request]) } catch {
        DispatchQueue.main.async {
          completion(FSELicenseScanResult(
            fullText: "",
            name: nil,
            licenseNumber: nil,
            classifiedLicences: [],
            dobISO8601: nil,
            telephone: nil,
            residency: nil
          ))
        }
      }
    }
  }

  // MARK: - Region detection

  private static func isBCNonTidal(fullText: String) -> Bool {
    let l = fullText.lowercased()
    return l.contains("non-tidal angling licence")
      || l.contains("non-tidal angling license")
      || l.contains("british columbia")
      || l.contains("www.gov.bc.ca/fish-licence")
      || l.contains("angler number")
  }

  // -------------------------
  // MARK: BC Non-tidal Parser (25/26 layout)

  // -------------------------

  private static func parseBCNonTidal(
    fullText: String,
    lines: [OCRLine]
  ) -> (
    name: String?,
    license: String?,
    rows: [ClassifiedLicenceParse],
    dobISO8601: String?,
    telephone: String?,
    residency: String?
  )? {
    let linesTB = lines // already top->bottom

    // Estimate LEFT COLUMN bound (maxX)
    let leftKeys = [
      "licencee",
      "licensee",
      "angler number",
      "date of birth",
      "dob",
      "mailing address",
      "telephone",
      "residency"
    ]
    let leftColumnMaxX: CGFloat = {
      let lefts = linesTB.filter { line in
        let lo = line.text.lowercased()
        return leftKeys.contains(where: { lo.contains($0) })
      }
      let mx = lefts.map(\.maxX).max() ?? 0.5
      return min(mx + 0.02, 0.55)
    }()
    AppLogging.log({ String(format: "Left column maxX: %.3f", leftColumnMaxX) }, level: .debug, category: .ocr)

    func dumpLeftColumnLines(_ note: String) {
      AppLogging.log({ "— left column lines (\(note)) —" }, level: .debug, category: .ocr)
      for (i, l) in linesTB.enumerated() where l.minX <= leftColumnMaxX + 0.02 {
        AppLogging.log({ String(format: "  [L%03d] x=%.3f..%.3f y=%.3f %@", i, l.minX, l.maxX, l.midY, l.text) }, level: .debug, category: .ocr)
      }
    }
    dumpLeftColumnLines("initial")

    // 1) Angler Number (acts as license number for this doc)
    var anglerNumber: String?
    if let anglerRegex = try? NSRegularExpression(pattern: #"(?i)\bAngler\s*Number\b[:\s]*([A-Z0-9\-]+)"#) {
      for l in linesTB {
        let ns = l.text as NSString
        if let m = anglerRegex.firstMatch(in: l.text, range: NSRange(location: 0, length: ns.length)) {
          let r = m.range(at: 1)
          if r.location != NSNotFound {
            let token = ns.substring(with: r).trimmingCharacters(in: .whitespaces)
            if token.count >= 5 { anglerNumber = token }
          }
        }
      }
    }
    if anglerNumber == nil {
      for l in linesTB where l.minX <= leftColumnMaxX && l.text.lowercased().contains("angler number") {
        let tok = l.text.components(separatedBy: CharacterSet.alphanumerics.inverted)
          .first(where: { $0.rangeOfCharacter(from: .decimalDigits) != nil && $0.count >= 5 })
        if let t = tok { anglerNumber = t; break }
      }
    }

    // 2) Licencee name (LAST, FIRST)
    let licenceeLabels = ["licencee", "licensee"]
    var nameResult: String?
    // ✅ Keep this clean version
    if let labelIdx =
      FSEBCFuzzyPatches.indexOfLabelFuzzy("licencee", in: linesTB) ??
      FSEBCFuzzyPatches.indexOfLabelFuzzy("licensee", in: linesTB) ??
      linesTB.firstIndex(where: { line in
        let lo = line.text.lowercased()
        return licenceeLabels.contains(where: { lo.contains($0) })
      }) {
      let label = linesTB[labelIdx]

      if let same = valueAfterDelimiter(in: label.text) {
        let v = same.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lf = extractLastCommaFirst(from: v) { nameResult = lf }
      }
      if nameResult == nil {
        if let neighbor = bestNameNeighbor(
          for: labelIdx,
          lines: linesTB,
          leftColumnMaxX: leftColumnMaxX,
          yTolerance: 0.03,
          maxDX: 0.50
        ) {
          let raw = neighbor.text.trimmingCharacters(in: .whitespacesAndNewlines)
          AppLogging.log({ "NAME best neighbor raw: \(raw)" }, level: .debug, category: .ocr)
          if let lf = extractLastCommaFirst(from: raw) {
            nameResult = lf
          } else {
            AppLogging.log("NAME neighbor didn’t parse as LAST, FIRST", level: .debug, category: .ocr)
          }
        } else {
          AppLogging.log("NAME no neighbor found in window", level: .debug, category: .ocr)
        }
      }

      if nameResult == nil {
        let lookahead = linesTB.dropFirst(labelIdx + 1).prefix(5)
        for l in lookahead where l.minX <= leftColumnMaxX {
          if let lf = extractLastCommaFirst(from: l.text) { nameResult = lf; break }
        }
      }
    }

    // --- DEBUG name ---
    if let n = nameResult {
      AppLogging.log({ "NAME parsed -> \(n)" }, level: .info, category: .ocr)
    } else {
      AppLogging.log("NAME not parsed from left column", level: .warn, category: .ocr)
    }

    // Helper: find label index
    // Helper: find label index (now fuzzy)
    func indexOfLabel(containing needle: String) -> Int? {
      if let i = FSEBCFuzzyPatches.indexOfLabelFuzzy(needle, in: linesTB) { return i }
      return linesTB.firstIndex { $0.text.lowercased().contains(needle) }
    }

    // 3) DOB (content-aware: prefer date-shaped candidate; allow above or below)
    var dobISO: String?
    if let i = indexOfLabel(containing: "date of birth") ?? indexOfLabel(containing: "dob") {
      AppLogging.log({ "DOB label at index: \(i) | line: \(linesTB[i].text) | bbox: \(fmt(linesTB[i].bbox))" }, level: .debug, category: .ocr)

      if let raw = nearestLeftColumnMatch(
        toLabelAt: i,
        lines: linesTB,
        leftColumnMaxX: leftColumnMaxX,
        yTolerance: 0.03,
        maxDX: 0.50,
        includeAbove: true,
        includeBelow: true,
        preferPattern: #"(?i)^(?:[A-Z]{3}\s+\d{1,2},?\s+\d{4}|\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})$"#
      ) {
        AppLogging.log({ "DOB matched neighbor: \(raw)" }, level: .debug, category: .ocr)
        dobISO = normalizeDOBToISO(raw)
        AppLogging.log({ "normalizeDOBToISO -> \(dobISO ?? "nil")" }, level: .debug, category: .ocr)
      }

      if dobISO == nil {
        let window = leftColumnWindowText(around: i, lines: linesTB, leftColumnMaxX: leftColumnMaxX, lookahead: 6)
        AppLogging.log({ "DOB window (left column): \(window)" }, level: .debug, category: .ocr)
        if let token = firstMatch(in: window, pattern: #"(?i)[A-Z]{3}\s+\d{1,2},?\s+\d{4}"#, group: 0) {
          AppLogging.log({ "DOB regex token: \(token)" }, level: .debug, category: .ocr)
          dobISO = normalizeDOBToISO(token)
          AppLogging.log({ "normalizeDOBToISO(token) -> \(dobISO ?? "nil")" }, level: .debug, category: .ocr)
        } else {
          AppLogging.log("DOB regex token: nil", level: .debug, category: .ocr)
        }
      }
    } else {
      AppLogging.log("DOB label not found", level: .debug, category: .ocr)
    }

    // 4) Telephone (same as before; left column)
    var telOut: String?
    if let i = indexOfLabel(containing: "telephone") {
      AppLogging.log({ "TEL label at index: \(i) | line: \(linesTB[i].text) | bbox: \(fmt(linesTB[i].bbox))" }, level: .debug, category: .ocr)
      let near = valueNearLeft(labelIndex: i, lines: linesTB, leftColumnMaxX: leftColumnMaxX)
      AppLogging.log({ "valueNearLeft(TEL) raw: \(near ?? "nil")" }, level: .debug, category: .ocr)
      if let n = near { telOut = extractTelephone(from: [n]) }
      if telOut == nil {
        let window = leftColumnWindowText(around: i, lines: linesTB, leftColumnMaxX: leftColumnMaxX, lookahead: 4)
        AppLogging.log({ "TEL window (left column): \(window)" }, level: .debug, category: .ocr)
        telOut = extractTelephone(from: [window])
      }
      AppLogging.log({ "TEL parsed: \(telOut ?? "nil")" }, level: .debug, category: .ocr)
    } else {
      AppLogging.log("TEL label not found", level: .debug, category: .ocr)
    }

    // 5) Residency (content-aware: prefer “resident” phrasing; allow above)
    var residencyOut: String?
    if let i = indexOfLabel(containing: "residency") {
      AppLogging.log({ "RES label at index: \(i) | line: \(linesTB[i].text) | bbox: \(fmt(linesTB[i].bbox))" }, level: .debug, category: .ocr)

      var raw = nearestLeftColumnMatch(
        toLabelAt: i,
        lines: linesTB,
        leftColumnMaxX: leftColumnMaxX,
        yTolerance: 0.03,
        maxDX: 0.60,
        includeAbove: true,
        includeBelow: true,
        preferPattern: #"(?i)\b(?:b\.?\s*c\.?\s*resident|bc\s*resident|british\s+columbia\s+resident|not\s+a\s+canadian\s+resident)\b"#
      )
      AppLogging.log({ "RES neighbor raw: \(raw ?? "nil")" }, level: .debug, category: .ocr)

      if raw == nil {
        let window = leftColumnWindowText(around: i, lines: linesTB, leftColumnMaxX: leftColumnMaxX, lookahead: 6)
        AppLogging.log({ "RES window (left column): \(window)" }, level: .debug, category: .ocr)
        raw = firstMatch(
          in: window,
          pattern: #"(?i)\b(?:b\.?\s*c\.?\s*resident|bc\s*resident|british\s+columbia\s+resident|not\s+a\s+canadian\s+resident)\b"#,
          group: 0
        )
        AppLogging.log({ "RES regex token: \(raw ?? "nil")" }, level: .debug, category: .ocr)
      }
      residencyOut = normalizeResidency(raw: raw)
      AppLogging.log({ "RES normalized -> \(residencyOut ?? "nil")" }, level: .debug, category: .ocr)
    } else {
      AppLogging.log("RES label not found", level: .debug, category: .ocr)
    }

    // Helper: find best name neighbor
    func bestNameNeighbor(
      for labelIndex: Int,
      lines: [OCRLine],
      leftColumnMaxX: CGFloat,
      yTolerance: CGFloat,
      maxDX: CGFloat
    ) -> OCRLine? {
      guard labelIndex < lines.count else { return nil }
      let label = lines[labelIndex]
      let candidates = lines.enumerated().compactMap { idx, l -> OCRLine? in
        if idx == labelIndex { return nil }
        if l.minX > leftColumnMaxX + 0.02 { return nil }
        if abs(l.midY - label.midY) > yTolerance { return nil }
        if (l.minX - label.maxX) > maxDX { return nil }
        if looksLikeAnotherLabel(l.text) || looksLikeHeader(l.text) { return nil }
        return l
      }
      return candidates.first
    }

    // 6) Classified Waters table (call companion extractor)
    AppLogging.log({ "Classified Waters: starting extraction (lines=\(linesTB.count))" }, level: .debug, category: .ocr)
    let rows = BCClassifiedWaters.parse(lines: linesTB)
    AppLogging.log({ "Classified Waters: extracted \(rows.count) row(s)" }, level: .info, category: .ocr)
    if !rows.isEmpty {
      let preview = rows.prefix(3).map { "\($0.licNumber)|\($0.water)" }.joined(separator: ", ")
      AppLogging.log({ "Classified Waters: preview=\(preview)" }, level: .debug, category: .ocr)
    }

    if anglerNumber != nil || nameResult != nil || !rows
      .isEmpty || dobISO != nil || telOut != nil || residencyOut != nil {
      return (nameResult, anglerNumber, rows, dobISO, telOut, residencyOut)
    }
    return nil
  }

  // -------------------------
  // MARK: Generic fallback (lightweight)

  // -------------------------

  private static func parseGeneric(
    fullText: String,
    lines: [OCRLine]
  ) -> (name: String?, license: String?, dobISO8601: String?, telephone: String?, residency: String?) {
    let texts = lines.map(\.text)
    let license = extractLicenseNumber(from: texts, fallbackFrom: fullText)

    // Name (cheap heuristics)
    var nameOut: String?
    if let fromLabels = extractNameFromLabeledLines(texts) { nameOut = fromLabels } else if let fromComma = extractLastCommaFirst(from: texts) { nameOut = fromComma } else if let fromHeur = extractNameByHeuristics(texts) { nameOut = fromHeur }

    let dobISO = normalizeDOBToISO(
      firstMatch(
        in: fullText,
        pattern: #"(?i)(?:date of birth|dob)[:\s\-]*([A-Z]{3}\s+\d{1,2},?\s+\d{4}|\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})"#,
        group: 1
      ) ?? ""
    )
    let telephone = extractTelephone(from: [fullText])

    var residency: String?
    if let raw = firstMatch(in: fullText, pattern: #"(?i)\bresidency\b[:\s\-]*([^\n\r]+)"#, group: 1) {
      residency = normalizeResidency(raw: raw)
    }

    return (nameOut, license, dobISO, telephone, residency)
  }

  private static func extractLicenseNumber(from lines: [String], fallbackFrom full: String) -> String? {
    let keywordPattern = #"(?i)\b(license|licence|lic|dl|id|angler|no\.?|number|permit)\b[:\s\-]*([A-Z0-9\-]{5,20})"#
    for t in lines {
      if let m = t.range(of: keywordPattern, options: .regularExpression) {
        let sub = String(t[m])
        if let id = sub.components(separatedBy: CharacterSet.alphanumerics.inverted).last, id.count >= 5 {
          return id
        }
      }
    }
    let fallbackPattern = #"[A-Z0-9]{6,14}"#
    let tokens = full.components(separatedBy: CharacterSet.alphanumerics.inverted)
    // ✅ correct
    for t in tokens where t.range(of: fallbackPattern, options: .regularExpression) != nil &&
      t.rangeOfCharacter(from: .decimalDigits) != nil {
      return t
    }
    return nil
  }

  private static func extractNameFromLabeledLines(_ lines: [String]) -> String? {
    let labels = [
      "licencee",
      "licensee",
      "name",
      "holder",
      "cardholder",
      "surname",
      "last",
      "family name",
      "given",
      "first"
    ]
    for (idx, t) in lines.enumerated() {
      let lower = t.lowercased()
      if labels.contains(where: { lower.contains($0) }) {
        if let v = valueAfterDelimiter(in: t), isNameCandidate(v) { return normalizeNameGuessingComma(v) }
        if idx + 1 < lines.count {
          let n = lines[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
          if isNameCandidate(n) { return normalizeNameGuessingComma(n) }
        }
      }
    }
    return nil
  }

  private static func extractLastCommaFirst(from lines: [String]) -> String? {
    for t in lines {
      if containsDigits(t) || containsMonthWord(t) || isBoilerplate(t) { continue }
      if let s = extractLastCommaFirst(from: t) { return s }
    }
    return nil
  }

  private static func extractLastCommaFirst(from text: String) -> String? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.contains(",") else { return nil }
    let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count >= 2 else { return nil }
    var left = String(parts[0])
    let right = parts[1]
    if containsDigits(left) || containsDigits(String(right)) { return nil }
    if containsMonthWord(left) || containsMonthWord(String(right)) { return nil }
    if isBoilerplate(left) || isBoilerplate(String(right)) { return nil }
    if left == left.uppercased() { left = fixCommonOCRErrorsInSurname(left) }
    let last = smartTitlecase(left)
    let first = right.split(separator: " ").first.map { smartTitlecase(String($0)) } ?? ""
    let composed = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    return composed.isEmpty ? nil : composed
  }

  private static func extractNameByHeuristics(_ lines: [String]) -> String? {
    let blacklist = headerOrLabelWords
    let cands = lines
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { s in
        let l = s.lowercased()
        return !blacklist.contains(where: { l.contains($0) }) &&
          !containsDigits(s) && !containsMonthWord(s) && !isBoilerplate(s)
      }
      .filter { isNameCandidate($0) }
    let scored = cands.map { ($0, nameScore($0)) }.sorted { $0.1 > $1.1 }
    if let best = scored.first { return smartTitlecase(best.0) }
    return nil
  }

  // MARK: - Labeling helpers used above

  private static let headerOrLabelWords: [String] = [
    "date of birth", "dob", "telephone", "residency",
    "issue date", "valid from", "valid to", "vendor",
    "species", "water", "basic licence", "conservation surcharge",
    "classified waters", "non-refundable", "non-transferable",
    "non refundable", "non transferable",
    "licence must be carried", "recording instructions", "please note"
  ]

  private static func isBoilerplate(_ s: String) -> Bool {
    let l = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let norm = l.replacingOccurrences(of: "-", with: " ")
    if norm.contains("non refundable") || norm.contains("non transferable") { return true }
    if norm.contains("please note") || norm.contains("recording instructions") { return true }
    if norm.contains("licence must be carried") { return true }
    return false
  }

  private static func looksLikeHeader(_ s: String) -> Bool {
    let l = s.trimmingCharacters(in: .whitespaces).lowercased()
    return headerOrLabelWords.contains(where: { l.contains($0) })
  }

  private static func looksLikeAnotherLabel(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasSuffix(":") { return true }
    let l = t.lowercased()
    let labelWords = [
      "name", "licencee", "licensee", "angler", "number", "date of birth", "dob",
      "telephone", "residency", "issue date", "valid from", "valid to", "vendor"
    ]
    return labelWords.contains(where: { l.contains($0) })
  }

  private static func valueAfterDelimiter(in text: String) -> String? {
    if let r = text.range(of: ":", options: .literal) {
      let v = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
      return v.isEmpty ? nil : v
    }
    if let r = text.range(of: "-", options: .literal) {
      let v = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
      return v.isEmpty ? nil : v
    }
    return nil
  }

  private static func nearestRightNeighbor(
    for label: OCRLine,
    in lines: [OCRLine],
    yTolerance: CGFloat,
    maxDX: CGFloat,
    leftColumnMaxX: CGFloat
  ) -> OCRLine? {
    let candidates = lines
      .filter { $0.minX > label.maxX }
      .filter { $0.minX <= leftColumnMaxX }
      .filter { ($0.minX - label.maxX) <= maxDX }
      .filter { abs($0.midY - label.midY) <= yTolerance }
      .sorted { ($0.minX - label.maxX) < ($1.minX - label.maxX) }
    return candidates.first(where: { !looksLikeAnotherLabel($0.text) && !looksLikeHeader($0.text) })
  }

  // Left-column constrained value fetch (generic)
  private static func valueNearLeft(
    labelIndex: Int,
    lines: [OCRLine],
    leftColumnMaxX: CGFloat
  ) -> String? {
    let label = lines[labelIndex]

    if let v = valueAfterDelimiter(in: label.text) {
      let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { return t }
    }

    let rightCandidates = lines
      .filter { $0.minX > label.maxX }
      .filter { $0.minX <= leftColumnMaxX + 0.02 }
      .filter { ($0.minX - label.maxX) <= 0.45 }
      .filter { abs($0.midY - label.midY) <= 0.03 }

    if let neighbor = rightCandidates
      .sorted(by: { ($0.minX - label.maxX) < ($1.minX - label.maxX) })
      .first(where: { !looksLikeAnotherLabel($0.text) && !looksLikeHeader($0.text) }) {
      let t = neighbor.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { return t }
    }

    for k in 1 ... 6 {
      let idx = labelIndex + k
      guard idx < lines.count else { break }
      let cand = lines[idx]
      if cand.minX > leftColumnMaxX + 0.02 { break }
      if looksLikeAnotherLabel(cand.text) || looksLikeHeader(cand.text) { break }
      let t = cand.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty, t.lowercased() != "n/a" { return t }
    }
    return nil
  }

  // Content-aware neighbor: search LEFT column around a label for text that matches a pattern.
  // Can consider above and/or below the label, within yTolerance and maxDX.
  private static func nearestLeftColumnMatch(
    toLabelAt labelIndex: Int,
    lines: [OCRLine],
    leftColumnMaxX: CGFloat,
    yTolerance: CGFloat,
    maxDX: CGFloat,
    includeAbove: Bool,
    includeBelow: Bool,
    preferPattern: String
  ) -> String? {
    guard let rx = try? NSRegularExpression(pattern: preferPattern, options: []) else { return nil }
    let label = lines[labelIndex]

    // Collect candidates near the same row (both above/below if requested)
    let candidates = lines.enumerated().compactMap { idx, l -> (i: Int, line: OCRLine)? in
      if idx == labelIndex { return nil }
      // left column only
      if l.minX > leftColumnMaxX + 0.02 { return nil }
      // close in X to the right (typical layout), allow small left shift in case of OCR jitter
      if (l.minX - label.maxX) > maxDX { return nil }
      // limit vertical distance
      let dy = abs(l.midY - label.midY)
      if dy > yTolerance { return nil }

      // directional constraint if requested
      if !includeAbove, l.midY > label.midY { return nil }
      if !includeBelow, l.midY < label.midY { return nil }

      // exclude other labels/headers
      if looksLikeAnotherLabel(l.text) || looksLikeHeader(l.text) { return nil }
      return (idx, l)
    }

    // Score: (1) pattern match; (2) smaller |dx|; (3) smaller |dy|
    func score(_ c: (i: Int, line: OCRLine)) -> (matched: Bool, dx: CGFloat, dy: CGFloat) {
      let ns = c.line.text as NSString
      let range = NSRange(location: 0, length: ns.length)
      let match = rx.firstMatch(in: c.line.text, options: [], range: range) != nil
      let dx = abs(c.line.minX - label.maxX)
      let dy = abs(c.line.midY - label.midY)
      return (match, dx, dy)
    }

    let best = candidates.sorted { a, b in
      let sa = score(a), sb = score(b)
      if sa.matched != sb.matched { return sa.matched && !sb.matched }
      if sa.dx != sb.dx { return sa.dx < sb.dx }
      return sa.dy < sb.dy
    }.first

    return best?.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Build a left-column window of text around a label
  private static func leftColumnWindowText(
    around labelIndex: Int,
    lines: [OCRLine],
    leftColumnMaxX: CGFloat,
    lookahead: Int
  ) -> String {
    let lo = max(0, labelIndex - 1)
    let hi = min(lines.count - 1, labelIndex + lookahead)
    return lines[lo ... hi]
      .filter { $0.minX <= leftColumnMaxX + 0.02 }
      .map(\.text)
      .joined(separator: " ")
  }

  // MARK: - Normalizers

  private static func normalizeDOBToISO(_ raw: String) -> String? {
    DateParsingUtilities.normalizeDOBToISO(raw)
  }

  private static func extractTelephone(from lines: [String]) -> String? {
    let joined = lines.joined(separator: " ")
    let pattern = #"(?x)(?:(?:\+?1[\s\.\-]?)?\(?\d{3}\)?[\s\.\-]?\d{3}[\s\.\-]?\d{4})"#
    return firstMatch(in: joined, pattern: pattern, group: 0)
  }

  private static func normalizeResidency(raw: String?) -> String? {
    let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if r.contains("not a canadian resident") { return "NOT A CANADIAN RESIDENT" }
    if r.contains("b.c. resident") || r.contains("bc resident") || r.contains("british columbia resident") {
      return "B.C. Resident"
    }
    return nil
  }

  // MARK: - Misc helpers

  private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
    guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = text as NSString
    if let m = rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
      let r = m.range(at: group)
      if r.location != NSNotFound { return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return nil
  }

  // MARK: - Name helpers (minimal)

  private static func isNameCandidate(_ s: String) -> Bool {
    if looksLikeHeader(s) || looksLikeAnotherLabel(s) || isBoilerplate(s) { return false }
    if containsDigits(s) || containsMonthWord(s) { return false }
    if s.contains(",") { return true }
    let words = s
      .replacingOccurrences(of: ",", with: " ")
      .split(whereSeparator: { !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-\' ".contains($0) })
      .map(String.init)
      .filter { !$0.isEmpty }
    return (2 ... 3).contains(words.count)
  }

  private static func nameScore(_ s: String) -> Double {
    let words = s.split(separator: " ")
    var score = 0.0
    if (2 ... 3).contains(words.count) { score += 1.0 }
    if s.rangeOfCharacter(from: .decimalDigits) == nil { score += 0.5 }
    if s == s.uppercased() || s == s.capitalized { score += 0.3 }
    if words.count == 1 || words.count > 4 { score -= 0.5 }
    return score
  }

  private static func containsDigits(_ s: String) -> Bool {
    s.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
  }

  private static func containsMonthWord(_ s: String) -> Bool {
    let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"]
    let l = s.lowercased()
    return months.contains(where: { l.contains($0) })
  }

  fileprivate static func fixCommonOCRErrorsInSurname(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return raw }
    let isAllCaps = s == s.uppercased()
    guard isAllCaps else { return raw }
    if s.hasPrefix("MO"), s.count >= 3 {
      let restLower = s.dropFirst(2).lowercased()
      let mcStems: [String] = [
        "minn", "donald", "dougall", "intyre", "innis", "inally", "inley", "innon", "mahon", "michael", "murray",
        "pherson", "gregor", "bride", "neil", "dermott", "arthur", "allister", "cauley", "ivor", "gowan", "gee", "leod",
        "lagan", "quarrie", "fadden", "cann", "kenzie", "kinna", "kinnon", "millan"
      ]
      let looksMc = mcStems.contains { stem in
        restLower.hasPrefix(stem) || restLower.hasPrefix(String(stem.prefix(3)))
      }
      if looksMc {
        s.replaceSubrange(s.startIndex ..< s.index(s.startIndex, offsetBy: 2), with: "MC")
      }
    }
    return s
  }

  fileprivate static func smartTitlecase(_ s: some StringProtocol) -> String {
    func capWord(_ raw: String) -> String {
      var w = raw.lowercased()
      if w.hasPrefix("mc"), w.count > 2 {
        let i = w.index(w.startIndex, offsetBy: 2)
        w.replaceSubrange(w.startIndex ... w.startIndex, with: String(w[w.startIndex]).uppercased())
        w.replaceSubrange(i ... i, with: String(w[i]).uppercased())
        return w
      }
      if w.hasPrefix("mac"), w.count > 3 {
        let i = w.index(w.startIndex, offsetBy: 3)
        w.replaceSubrange(w.startIndex ... w.startIndex, with: String(w[w.startIndex]).uppercased())
        w.replaceSubrange(i ... i, with: String(w[i]).uppercased())
        return w
      }
      if let f = w.first {
        w.replaceSubrange(w.startIndex ... w.startIndex, with: String(f).uppercased())
      }
      return w
    }
    return s.split(separator: " ").map { word in
      word.split(separator: "-").map { capWord(String($0)) }.joined(separator: "-")
    }.joined(separator: " ")
  }
}

// MARK: - File-scope helpers (name only)

private func normalizeNameGuessingComma(_ s: String) -> String {
  let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
  if t.contains(",") {
    let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    if parts.count >= 2 {
      var left = String(parts[0])
      let right = parts[1]
      if left == left.uppercased() {
        left = FSELicenseTextRecognizer.fixCommonOCRErrorsInSurname(left)
      }
      let last = FSELicenseTextRecognizer.smartTitlecase(left)
      let first = right.split(separator: " ").first.map { FSELicenseTextRecognizer.smartTitlecase(String($0)) } ?? ""
      return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }
  }
  return FSELicenseTextRecognizer.smartTitlecase(t)
}
