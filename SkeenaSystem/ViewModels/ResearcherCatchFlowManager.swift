// Bend Fly Shop
// ResearcherCatchFlowManager.swift — Step-by-step confirmation flow for researcher catch recording.
//
// Encapsulates the researcher-specific conversational flow:
//   1. Identification — confirm species, lifecycle, sex (and location context)
//   2. Measurements  — show length/girth/weight calculated with confirmed species
//   3. Length confirmation
//   4. Girth confirmation
//   5. Final summary
//   6. Voice memo
//
// Species must be confirmed BEFORE measurements are shown, because the weight
// formula divisor depends on the species + river combination.
// Weight is always derived (never confirmed separately).
// Owned by CatchChatViewModel; only instantiated when the user role is .researcher.

import Combine
import Foundation

final class ResearcherCatchFlowManager: ObservableObject {

  // MARK: - Step Definitions

  enum Step: Equatable {
    case identification         // show location, species, lifecycle, sex for confirmation
    case confirmLength          // show estimated length, confirm or edit
    case confirmGirth           // show length + estimated girth, confirm or edit girth
    case finalSummary           // show all confirmed values + derived weight
    case floyTag                // ask for Floy Tag number (skip or enter)
    case scaleSample            // ask about scale sample (skip or scan barcode)
    case voiceMemo              // offer voice memo
    case complete
  }

  // MARK: - Published State

  @Published var currentStep: Step = .identification

  /// Anchor ID for the current step's Next/Confirm buttons in the chat UI.
  @Published var confirmAnchorID: UUID?

  // Confirmed values (initialized from ML analysis, updated by user)
  @Published var species: String?
  @Published var lifecycleStage: String?
  @Published var sex: String?
  @Published var lengthInches: Double?
  @Published var girthInches: Double?
  @Published var weightLbs: Double?

  // Estimation flags
  @Published var girthIsEstimated: Bool = true
  @Published var weightIsEstimated: Bool = true

  // Estimation metadata
  @Published var divisor: Int = FishWeightEstimator.defaultDivisor
  @Published var divisorSource: String = "Default"
  @Published var girthRatio: Double = FishWeightEstimator.defaultGirthRatio
  @Published var girthRatioSource: String = "Default (freshwater average)"

  // Initial measurement estimates (captured when identification is confirmed,
  // BEFORE user edits length/girth). These use the confirmed species/divisor,
  // so they're meaningful for model training.
  var initialLengthForMeasurements: Double?
  var initialGirthInches: Double?
  var initialWeightLbs: Double?
  var initialGirthIsEstimated: Bool = true
  var initialWeightIsEstimated: Bool = true
  var initialDivisor: Int = FishWeightEstimator.defaultDivisor
  var initialDivisorSource: String = "Default"
  var initialGirthRatio: Double = FishWeightEstimator.defaultGirthRatio
  var initialGirthRatioSource: String = "Default (freshwater average)"

  // Floy tag and scale sample (mock — not persisted yet)
  @Published var floyTagNumber: String?
  @Published var scaleSampleBarcode: String?

  // Length estimation source (updated when species correction triggers re-estimation)
  var lengthSource: LengthEstimateSource?

  // River context (from analysis, used for divisor lookup)
  var riverName: String?

  // Original ML-detected species (for detecting if user changed it)
  var originalSpecies: String?
  var originalLifecycleStage: String?

  /// Whether the researcher changed the species from the original ML detection.
  var speciesWasCorrected: Bool {
    let current = species?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let original = originalSpecies?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return current != original
  }

  /// Callback for posting assistant messages to the chat. Set by CatchChatViewModel.
  var postMessage: ((String) -> UUID)?

  // MARK: - Initialization

  /// Initialize from ML analysis results.
  /// Does NOT compute girth/weight yet — those depend on species, which must be
  /// confirmed first. Initial measurement estimates are snapshotted when the
  /// identification step is confirmed (see `confirm()`).
  func initialize(
    species: String?,
    lifecycleStage: String?,
    sex: String?,
    lengthInches: Double?,
    riverName: String?
  ) {
    self.species = species
    self.lifecycleStage = lifecycleStage
    self.sex = sex
    self.lengthInches = lengthInches
    self.riverName = riverName
    self.originalSpecies = species
    self.originalLifecycleStage = lifecycleStage

    currentStep = .identification
  }

  // MARK: - Step Advancement

  /// Confirm the current step and advance to the next one. Returns the message to post.
  func confirm() -> String {
    switch currentStep {
    case .identification:
      // Species/sex/lifecycle confirmed — now calculate measurements for the first time
      // using the confirmed species (which determines the correct divisor + regressor path).
      // Note: if species was corrected, the ViewModel has already re-estimated length
      // via reEstimateLengthForCorrectedSpecies() before calling confirm().
      recalculate()

      // Snapshot the initial measurement estimates AFTER species confirmation.
      // These reflect the first estimates shown to the researcher (computed with
      // the correct species/divisor). Comparing initial vs. final measurements
      // provides training data for improving the estimation formula.
      snapshotInitialEstimates()

      currentStep = .confirmLength
      return lengthPrompt()

    case .confirmLength:
      // Length confirmed — recalculate girth/weight with confirmed length, show girth
      recalculate()
      currentStep = .confirmGirth
      return girthPrompt()

    case .confirmGirth:
      // After girth is confirmed, go straight to final summary (weight is derived)
      recalculateWeightOnly()
      currentStep = .finalSummary
      return finalAnalysisText()

    case .finalSummary:
      currentStep = .floyTag
      return "If there is a Floy Tag present, please enter the number below, or press Skip."

    case .floyTag:
      currentStep = .scaleSample
      return "Are you taking a Scale Sample?\nIf yes, use your camera to scan the barcode on the envelope."

    case .scaleSample:
      currentStep = .voiceMemo
      return "Would you like to add a voice memo for this catch?"

    case .voiceMemo:
      currentStep = .complete
      return "Saving catch now..."

    case .complete:
      return ""
    }
  }

  // MARK: - Edit Handling

  /// Apply a user correction at the current step, recalculate downstream values.
  /// Returns (message, shouldAutoAdvance).
  /// When a numeric value is entered for length or girth, it auto-advances to the next step.
  func applyEdit(_ text: String) -> (message: String, autoAdvance: Bool) {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    switch currentStep {
    case .identification:
      parseSpeciesSexEdit(text, lower: lower)
      // Don't recalculate yet — measurements aren't shown until confirmed
      return (identificationPrompt(), false)

    case .confirmLength:
      if let num = extractNumber(from: text) {
        lengthInches = num
        recalculate()
        // Auto-advance: entering a number counts as confirming length
        currentStep = .confirmGirth
        return (girthPrompt(), true)
      }
      return (lengthPrompt(), false)

    case .confirmGirth:
      if let num = extractNumber(from: text) {
        girthInches = num
        girthIsEstimated = false
        recalculateWeightOnly()
        // Auto-advance: entering a number counts as confirming girth
        currentStep = .finalSummary
        return (finalAnalysisText(), true)
      }
      return (girthPrompt(), false)

    case .floyTag:
      // Any text input is treated as the Floy Tag number → auto-advance
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        floyTagNumber = trimmed
        currentStep = .scaleSample
        return ("Floy Tag: \(trimmed)\n§\nAre you taking a Scale Sample?\nIf yes, use your camera to scan the barcode on the envelope.", true)
      }
      return ("If there is a Floy Tag present, please enter the number below, or press Skip.", false)

    default:
      return ("", false)
    }
  }

  // MARK: - Initial Estimate Snapshot

  /// Captures the current measurement values as the "initial estimates".
  /// Called once when transitioning from identification → measurements,
  /// AFTER species is confirmed and length has been re-estimated if needed.
  private func snapshotInitialEstimates() {
    initialLengthForMeasurements = lengthInches
    initialGirthInches = girthInches
    initialWeightLbs = weightLbs
    initialGirthIsEstimated = girthIsEstimated
    initialWeightIsEstimated = weightIsEstimated
    initialDivisor = divisor
    initialDivisorSource = divisorSource
    initialGirthRatio = girthRatio
    initialGirthRatioSource = girthRatioSource
  }

  // MARK: - Recalculation

  /// Recalculate girth and weight from current length, species, and river.
  func recalculate() {
    guard let length = lengthInches, length > 0 else {
      girthInches = nil
      weightLbs = nil
      return
    }

    if girthIsEstimated {
      // Full recalculation: girth + weight from length
      let estimate = FishWeightEstimator.estimate(
        lengthInches: length,
        species: species,
        river: riverName
      )
      girthInches = estimate.girthInches
      weightLbs = estimate.weightLbs
      divisor = estimate.divisor
      divisorSource = estimate.divisorSource
      girthRatio = estimate.girthRatio
      girthRatioSource = estimate.girthRatioSource
      weightIsEstimated = true
    } else {
      // Girth was manually set; only recalculate weight
      recalculateWeightOnly()
    }
  }

  /// Recalculate weight only (when girth was manually overridden).
  private func recalculateWeightOnly() {
    guard let length = lengthInches, length > 0,
          let girth = girthInches, girth > 0 else {
      weightLbs = nil
      return
    }

    let estimate = FishWeightEstimator.estimateWeight(
      lengthInches: length,
      girthInches: girth,
      species: species,
      river: riverName
    )
    weightLbs = estimate.weightLbs
    divisor = estimate.divisor
    divisorSource = estimate.divisorSource
    weightIsEstimated = true
  }

  // MARK: - Prompt Generation

  /// Identification step: show only species, lifecycle, sex (no measurements).
  func identificationSummary() -> String {
    var lines: [String] = []

    if let s = species, !s.isEmpty {
      if let stage = lifecycleStage, !stage.isEmpty {
        lines.append("Species: \(s) (\(stage))")
      } else {
        lines.append("Species: \(s)")
      }
    } else {
      lines.append("Species: Unknown")
    }

    if let sx = sex, !sx.isEmpty {
      lines.append("Sex: \(sx)")
    } else {
      lines.append("Sex: Unknown")
    }

    return lines.joined(separator: "\n")
  }

  /// Identification prompt shown when user edits species/sex.
  func identificationPrompt() -> String {
    let summary = identificationSummary()
    return "\(summary)\n§\nConfirm the species and sex, or type corrections."
  }

  private func lengthPrompt() -> String {
    let display = lengthInches.map { formatLength($0) } ?? "Unknown"
    return "Estimated length: \(display)\n§\nConfirm, or type a new value (e.g. \"32\")."
  }

  private func girthPrompt() -> String {
    let lengthDisplay = lengthInches.map { formatLength($0) } ?? "Unknown"
    let girthDisplay = girthInches.map { formatGirth($0) } ?? "Unknown"

    var lines: [String] = []
    lines.append("Length: \(lengthDisplay)")
    lines.append("Estimated girth: \(girthDisplay)")

    lines.append("§")
    if girthIsEstimated {
      lines.append("Girth estimated using \(girthRatio) x length ratio")
      lines.append("(\(girthRatioSource))")
    } else {
      lines.append("Using measured girth (not estimated)")
    }

    lines.append("")
    lines.append("Confirm the girth, or type a measured value.")

    return lines.joined(separator: "\n")
  }

  /// Final analysis showing derived weight with the inputs used for the calculation.
  func finalAnalysisText() -> String {
    var lines: [String] = ["Final Measurements"]
    lines.append("")

    if let r = riverName, !r.isEmpty {
      lines.append("Location: \(r)")
    }
    if let s = species, !s.isEmpty {
      if let stage = lifecycleStage, !stage.isEmpty {
        lines.append("Species: \(s) (\(stage))")
      } else {
        lines.append("Species: \(s)")
      }
    }
    if let sx = sex, !sx.isEmpty {
      lines.append("Sex: \(sx)")
    }
    if let l = lengthInches {
      lines.append("Length: \(formatLength(l))")
    }
    if let g = girthInches {
      let prefix = girthIsEstimated ? "~" : ""
      lines.append("Girth: \(prefix)\(formatGirth(g))")
    }
    if let w = weightLbs {
      lines.append("Weight: ~\(formatWeight(w))")
    }

    // Derivation details
    lines.append("§")
    lines.append("Calculation inputs:")
    lines.append("  Divisor: \(divisor) (\(divisorSource))")
    if girthIsEstimated {
      lines.append("  Girth ratio: \(girthRatio) x length (\(girthRatioSource))")
    } else {
      lines.append("  Girth: manually measured")
    }
    lines.append("  Formula: length x girth\u{00B2} / divisor")

    return lines.joined(separator: "\n")
  }

  /// Kept for backward compatibility (used by voice memo save path).
  func finalSummaryText() -> String {
    return finalAnalysisText()
  }

  // MARK: - Parsing Helpers

  // Known sex keywords — used to separate sex from species in free-text input
  private static let sexKeywords: Set<String> = ["male", "female", "hen", "buck"]

  // Lifecycle stage keywords — stripped from species candidate
  private static let stageKeywords: Set<String> = ["holding", "traveler", "spawning", "kelt", "smolt", "resident"]

  // Known species names the user might type (lowercase). Maps to display name.
  private static let knownSpecies: [String: String] = [
    "steelhead":        "Steelhead",
    "chinook":          "Chinook Salmon",
    "king":             "Chinook Salmon",
    "king salmon":      "Chinook Salmon",
    "chinook salmon":   "Chinook Salmon",
    "coho":             "Coho Salmon",
    "silver":           "Coho Salmon",
    "coho salmon":      "Coho Salmon",
    "rainbow":          "Rainbow Trout",
    "rainbow trout":    "Rainbow Trout",
    "sea-run trout":    "Sea-Run Trout",
    "sea run trout":    "Sea-Run Trout",
    "brown trout":      "Brown Trout",
    "brook trout":      "Brook Trout",
    "brook":            "Brook Trout",
    "cutthroat":        "Cutthroat Trout",
    "cutthroat trout":  "Cutthroat Trout",
    "arctic char":      "Arctic Char",
    "char":             "Arctic Char",
    "grayling":         "Grayling",
    "atlantic salmon":  "Atlantic Salmon",
    "largemouth bass":  "Largemouth Bass",
    "smallmouth bass":  "Smallmouth Bass",
    "northern pike":    "Northern Pike",
    "pike":             "Northern Pike",
    "pink salmon":      "Pink Salmon",
    "chum salmon":      "Chum Salmon",
    "sockeye salmon":   "Sockeye Salmon",
    "sockeye":          "Sockeye Salmon",
  ]

  private func parseSpeciesSexEdit(_ text: String, lower: String) {
    let tokens = lower.split { !$0.isLetter }.map(String.init)
    var speciesUpdated = false

    // Try to extract species via keyword pattern ("species: X" or "species is X")
    if let val = valueAfterKeyword("species", in: text, lower: lower) {
      species = val
      speciesUpdated = true
    }

    // Try to extract sex via keyword pattern ("sex: X" or "sex is X")
    if let val = valueAfterKeyword("sex", in: text, lower: lower) {
      sex = val.capitalized
    } else {
      // Infer sex from standalone keywords
      if tokens.contains("male") { sex = "Male" }
      else if tokens.contains("female") { sex = "Female" }
      else if tokens.contains("hen") { sex = "Hen" }
      else if tokens.contains("buck") { sex = "Buck" }
    }

    // Try to extract lifecycle stage (before species fallback so we can strip it)
    for keyword in Self.stageKeywords {
      if tokens.contains(keyword) {
        lifecycleStage = keyword.capitalized
        break
      }
    }

    // Fallback: if no "species:" keyword was found, check if the input
    // (minus sex and lifecycle keywords) matches a known species name.
    // This handles cases like "Steelhead", "Chinook male", "Steelhead Holding".
    if !speciesUpdated {
      // Strip sex and lifecycle keywords to isolate the species part
      let noiseWords = Self.sexKeywords.union(Self.stageKeywords)
      let speciesTokens = tokens.filter { !noiseWords.contains($0) }
      let candidate = speciesTokens.joined(separator: " ")

      if let displayName = Self.knownSpecies[candidate] {
        species = displayName
      } else if !candidate.isEmpty {
        // Not a recognized species but not a sex/stage keyword either —
        // treat as a species name (user may know something we don't)
        species = text.trimmingCharacters(in: .whitespacesAndNewlines)
          .components(separatedBy: " ")
          .filter { !noiseWords.contains($0.lowercased()) }
          .joined(separator: " ")
      }
    }
  }

  private func valueAfterKeyword(_ keyword: String, in text: String, lower: String) -> String? {
    guard let range = lower.range(of: keyword) else { return nil }
    let tail = text[range.upperBound...]
    if let isRange = tail.range(of: " is ") {
      return String(tail[isRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let colonRange = tail.range(of: ":") {
      return String(tail[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func extractNumber(from text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Try to find a number pattern
    if let range = trimmed.range(of: #"(\d+(\.\d+)?)"#, options: .regularExpression) {
      return Double(String(trimmed[range]))
    }
    return nil
  }

  // MARK: - Formatting

  private func formatLength(_ inches: Double) -> String {
    if inches.rounded() == inches {
      return "\(Int(inches)) inches"
    }
    return String(format: "%.1f inches", inches)
  }

  private func formatGirth(_ inches: Double) -> String {
    return String(format: "%.1f inches", inches)
  }

  private func formatWeight(_ lbs: Double) -> String {
    return String(format: "%.1f lbs", lbs)
  }
}
