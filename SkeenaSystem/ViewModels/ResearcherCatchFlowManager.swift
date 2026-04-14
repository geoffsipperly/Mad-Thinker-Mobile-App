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
    case studyParticipation     // "Are you participating in a study?" — Pit, Floy, Radio Telemetry
    case floyTagID              // conditional: enter Floy Tag ID (only if Floy selected)
    case sampleCollection       // "Are you taking a sample?" — Scale, Fin Tip, Both
    case scaleScan              // scan barcode for scale envelope
    case finTipScan             // scan barcode for fin tip envelope
    case voiceMemo              // offer voice memo
    case complete
  }

  /// Study type selected by the researcher (nil = not participating).
  enum StudyType: String, Equatable {
    case pit = "Pit"
    case floy = "Floy"
    case radioTelemetry = "Radio Telemetry"
  }

  /// Sample type selected by the researcher (nil = not taking a sample).
  enum SampleType: String, Equatable {
    case scale = "Scale"
    case finTip = "Fin Tip"
    case both = "Both"
  }

  // MARK: - Published State

  @Published var currentStep: Step = .identification

  /// Anchor ID for the current step's Next/Confirm buttons in the chat UI.
  @Published var confirmAnchorID: UUID?

  /// Whether the flow should include the post-measurement research steps
  /// (study participation, sample collection, barcode scans).
  ///
  /// - `true` (default): researcher role and guides with the Conservation
  ///   toggle ON — flow goes finalSummary → studyParticipation → … → voiceMemo.
  /// - `false`: guides with Conservation OFF — flow short-circuits
  ///   finalSummary → voiceMemo, skipping research-only steps.
  ///
  /// Not `@Published` because this is a one-shot mode flag set at initialize
  /// time, not a value the UI observes for live updates.
  var includeStudyAndSampleSteps: Bool = true

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

  // Study participation
  @Published var studyType: StudyType?
  @Published var floyTagNumber: String?

  // Sample collection
  @Published var sampleType: SampleType?
  @Published var scaleSampleBarcode: String?
  @Published var finTipSampleBarcode: String?

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
    AppLogging.log("[ResearcherFlow] Initialized: species=\(species ?? "nil") lifecycle=\(lifecycleStage ?? "nil") sex=\(sex ?? "nil") length=\(lengthInches.map { String($0) } ?? "nil")", level: .info, category: .research)
  }

  // MARK: - Step Advancement

  /// Confirm the current step and advance to the next one. Returns the message to post.
  func confirm() -> String {
    AppLogging.log("[ResearcherFlow] Confirming step: \(currentStep)", level: .debug, category: .research)
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
      // Length is required before we can compute girth or weight. If the ML
      // analyzer couldn't produce one and the user hasn't typed a measured
      // value yet, stay on this step and prompt them explicitly. This keeps
      // guides (Conservation OFF) from advancing with a nil length.
      guard lengthInches != nil else {
        return lengthPrompt()
      }
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
      // Guides with Conservation OFF skip the research-only post-measurement
      // steps and jump straight to the voice memo offer.
      if includeStudyAndSampleSteps {
        currentStep = .studyParticipation
        return "Are you participating in a study?"
      } else {
        currentStep = .voiceMemo
        return "Would you like to add a voice memo for this catch?"
      }

    case .studyParticipation:
      // "No" was selected (confirm = skip). Move to sample collection.
      studyType = nil
      currentStep = .sampleCollection
      return "Are you taking a sample?"

    case .floyTagID:
      // Floy tag submitted or skipped → sample collection
      currentStep = .sampleCollection
      return "Are you taking a sample?"

    case .sampleCollection:
      // "No" was selected. Move to voice memo.
      sampleType = nil
      currentStep = .voiceMemo
      return "Would you like to add a voice memo for this catch?"

    case .scaleScan:
      // Scale ID entered or skipped → check if fin tip also needed
      if sampleType == .both {
        currentStep = .finTipScan
        return "Now type the Fin Tip ID from the envelope."
      }
      currentStep = .voiceMemo
      return "Would you like to add a voice memo for this catch?"

    case .finTipScan:
      currentStep = .voiceMemo
      return "Would you like to add a voice memo for this catch?"

    case .voiceMemo:
      currentStep = .complete
      return ""

    case .complete:
      return ""
    }
  }

  // MARK: - Edit Handling

  /// Apply a user correction at the current step, recalculate downstream values.
  /// Returns (message, shouldAutoAdvance, recognized).
  /// - `recognized = false` means the input was rejected (empty, profane, or
  ///   unparseable); callers should show the message as-is without a
  ///   "Got it, updated:" prefix.
  /// When a numeric value is entered for length or girth, it auto-advances to
  /// the next step.
  func applyEdit(_ text: String) -> (message: String, autoAdvance: Bool, recognized: Bool) {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    // Global profanity screen — never persist profane text into species/ID
    // fields. Reply with the step-appropriate re-prompt.
    if Self.containsProfanity(text) {
      return (profanityReply(for: currentStep), false, false)
    }

    switch currentStep {
    case .identification:
      let recognized = parseSpeciesSexEdit(text, lower: lower)
      if !recognized {
        return (
          "I didn't catch that — please enter a species name (e.g., \"Steelhead\"), sex (male/female), or a lifecycle stage (holding, traveler, spawning, kelt, smolt, resident).",
          false,
          false
        )
      }
      // Don't recalculate yet — measurements aren't shown until confirmed
      return (identificationPrompt(), false, true)

    case .confirmLength:
      if let num = extractNumber(from: text) {
        lengthInches = num
        recalculate()
        // Auto-advance: entering a number counts as confirming length
        currentStep = .confirmGirth
        return (girthPrompt(), true, true)
      }
      return (
        "I didn't catch that — please enter the length in inches (e.g., 28 or 28.5).",
        false,
        false
      )

    case .confirmGirth:
      if let num = extractNumber(from: text) {
        girthInches = num
        girthIsEstimated = false
        recalculateWeightOnly()
        // Auto-advance: entering a number counts as confirming girth
        currentStep = .finalSummary
        return (finalAnalysisText(), true, true)
      }
      return (
        "I didn't catch that — please enter the girth in inches (e.g., 14 or 14.5).",
        false,
        false
      )

    case .floyTagID:
      // Store the Floy Tag ID but don't advance — show it for confirmation
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        floyTagNumber = trimmed
        return ("Floy Tag ID: \(trimmed)\n§\nConfirm, or type a corrected value.", false, true)
      }
      return ("Please enter the Floy Tag ID.", false, false)

    case .scaleScan:
      // Scale card ID is typed manually (no barcode scanner yet). Store the
      // value but don't advance — the user taps Confirm to continue.
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        scaleSampleBarcode = trimmed
        return ("Scale Card ID: \(trimmed)\n§\nConfirm, or type a corrected value.", false, true)
      }
      return ("Please enter the Scale Card ID.", false, false)

    case .finTipScan:
      // Fin tip envelope ID is typed manually. Same pattern as scaleScan.
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        finTipSampleBarcode = trimmed
        return ("Fin Tip ID: \(trimmed)\n§\nConfirm, or type a corrected value.", false, true)
      }
      return ("Please enter the Fin Tip ID.", false, false)

    default:
      // .studyParticipation, .sampleCollection, .voiceMemo, .finalSummary,
      // .complete — these are button-driven steps; typed input isn't expected.
      return (
        "I'm not expecting typed input right now — use the buttons above, or upload a new photo.",
        false,
        false
      )
    }
  }

  /// Step-appropriate re-prompt when the user's input was rejected by the
  /// profanity screen. Kept separate from the main switch so we don't mix
  /// rejection messaging into the happy-path prompts.
  private func profanityReply(for step: Step) -> String {
    switch step {
    case .identification:
      return "Let's keep it civil. Please enter a species name, sex (male/female), or a lifecycle stage."
    case .confirmLength:
      return "Let's keep it civil. Please enter the length in inches (e.g., 28 or 28.5)."
    case .confirmGirth:
      return "Let's keep it civil. Please enter the girth in inches (e.g., 14 or 14.5)."
    case .floyTagID:
      return "Let's keep it civil. Please enter the Floy Tag ID."
    case .scaleScan:
      return "Let's keep it civil. Please enter the Scale Card ID."
    case .finTipScan:
      return "Let's keep it civil. Please enter the Fin Tip ID."
    default:
      return "Let's keep it civil. Use the buttons above, or upload a new photo."
    }
  }

  // MARK: - Study & Sample Selection

  /// Called when the researcher selects a study type (Pit, Floy, Radio Telemetry).
  func selectStudy(_ type: StudyType) -> (message: String, nextStep: Step) {
    studyType = type

    if type == .floy {
      currentStep = .floyTagID
      return ("Study: \(type.rawValue)\n§\nPlease enter the Floy Tag ID.", .floyTagID)
    } else {
      // Pit and Radio Telemetry don't have follow-up yet
      currentStep = .sampleCollection
      return ("Study: \(type.rawValue)\n§\nAre you taking a sample?", .sampleCollection)
    }
  }

  /// Called when the researcher selects a sample type (Scale, Fin Tip, Both).
  func selectSample(_ type: SampleType) -> (message: String, nextStep: Step) {
    sampleType = type

    switch type {
    case .scale:
      currentStep = .scaleScan
      return ("Sample: \(type.rawValue)\n§\nType the Scale Card ID from the envelope.", .scaleScan)
    case .finTip:
      currentStep = .finTipScan
      return ("Sample: \(type.rawValue)\n§\nType the Fin Tip ID from the envelope.", .finTipScan)
    case .both:
      currentStep = .scaleScan
      return ("Sample: \(type.rawValue)\n§\nFirst, type the Scale Card ID.", .scaleScan)
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
    // When the ML analyzer couldn't estimate a length, ask the user to enter
    // one manually. Confirm has no meaning without a value to confirm.
    guard let length = lengthInches else {
      return "Length not detected from the photo.\n§\nPlease type a measured length in inches (e.g. \"32\") to continue."
    }
    return "Estimated length: \(formatLength(length))\n§\nConfirm, or type a new value (e.g. \"32\")."
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

  // MARK: - Parsing Helpers

  // Known sex keywords — used to separate sex from species in free-text input
  private static let sexKeywords: Set<String> = ["male", "female", "hen", "buck"]

  // Lifecycle stage keywords — stripped from species candidate
  private static let stageKeywords: Set<String> = ["holding", "traveler", "spawning", "kelt", "smolt", "resident"]

  // Lightweight profanity screen — keeps freeform input out of species/ID fields
  // when it would otherwise be stored verbatim and uploaded. Conservative list;
  // matches on whole-word tokens only (so "scunthorpe" won't trip "cunt").
  private static let profanityTokens: Set<String> = [
    "fuck", "fucking", "fucker", "fucked",
    "shit", "shitty", "bullshit",
    "bitch", "bitches",
    "cunt", "asshole", "bastard",
    "dick", "piss", "cock", "pussy", "twat", "wanker"
  ]

  /// Returns true if `text` contains any token from `profanityTokens`.
  /// Splits on non-letters so punctuation doesn't bypass the check.
  static func containsProfanity(_ text: String) -> Bool {
    let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
    for token in tokens where profanityTokens.contains(token) { return true }
    return false
  }

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

  /// Parse user's freeform identification edit. Returns `true` if we could
  /// recognize any species / sex / lifecycle content — callers use this to
  /// distinguish a real update from unparseable input (keyboard mashing,
  /// out-of-context chatter) and prompt the user again.
  private func parseSpeciesSexEdit(_ text: String, lower: String) -> Bool {
    let tokens = lower.split { !$0.isLetter }.map(String.init)
    var speciesUpdated = false
    var recognized = false

    // Try to extract species via keyword pattern ("species: X" or "species is X")
    if let val = valueAfterKeyword("species", in: text, lower: lower), !val.isEmpty {
      species = val
      speciesUpdated = true
      recognized = true
    }

    // Try to extract sex via keyword pattern ("sex: X" or "sex is X")
    if let val = valueAfterKeyword("sex", in: text, lower: lower), !val.isEmpty {
      sex = val.capitalized
      recognized = true
    } else {
      // Infer sex from standalone keywords
      if tokens.contains("male") { sex = "Male"; recognized = true }
      else if tokens.contains("female") { sex = "Female"; recognized = true }
      else if tokens.contains("hen") { sex = "Hen"; recognized = true }
      else if tokens.contains("buck") { sex = "Buck"; recognized = true }
    }

    // Try to extract lifecycle stage (before species fallback so we can strip it)
    for keyword in Self.stageKeywords {
      if tokens.contains(keyword) {
        lifecycleStage = keyword.capitalized
        recognized = true
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
        recognized = true
      } else if candidate.count >= 3 {
        // Not a recognized species but plausible enough to accept —
        // treat as a species name (user may know something we don't).
        // The ≥3-letter floor filters out "xx", stray punctuation, etc.
        species = text.trimmingCharacters(in: .whitespacesAndNewlines)
          .components(separatedBy: " ")
          .filter { !noiseWords.contains($0.lowercased()) }
          .joined(separator: " ")
        recognized = true
      }
    }

    return recognized
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
