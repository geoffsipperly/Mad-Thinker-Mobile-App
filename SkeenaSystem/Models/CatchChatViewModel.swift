// Bend Fly Shop

import AVFoundation
import Combine
import CoreLocation
import Foundation
import UIKit

enum ChatSender {
  case user
  case assistant
}

struct ChatMessage: Identifiable {
  let id = UUID()
  let sender: ChatSender
  let text: String?
  let image: UIImage?
}

final class CatchChatViewModel: ObservableObject {
  @Published var messages: [ChatMessage] = []
  @Published var userInput: String = ""
  @Published var isAssistantTyping: Bool = false

  // Show photo button inline after explainer
  @Published var showCaptureOptions: Bool = false

  // Voice notes attached to this catch (we currently keep the latest one only)
  @Published var attachedVoiceNotes: [LocalVoiceNote] = []

  // Show voice memo button next to a specific assistant message
  @Published var voiceMemoAnchorMessageID: UUID?

  // Show confirm button next to a specific assistant message (final save)
  @Published var confirmAnalysisMessageID: UUID?

  // Save flow
  @Published var saveRequested: Bool = false
  @Published var catchLog: String?

  // Context from the header
  @Published private(set) var guideName: String = ""
  @Published private(set) var currentAnglerName: String = ""

    // Latest device location (from ReportChatView)
    private var currentLocation: CLLocation?

    // Best timestamp for the current photo (EXIF or fallback)
    private var currentPhotoDate: Date?

  // Expose best photo timestamp (read-only)
  public var photoTimestamp: Date? { currentPhotoDate }

    // Latest analysis so we can update it from user corrections
    private var currentAnalysis: CatchPhotoAnalysis?

    // Initial analysis snapshot (before any user corrections)
    private var initialAnalysis: CatchPhotoAnalysis?

  // Saved photo filename (in PhotoStore)
  @Published var photoFilename: String?

  // Photo analyzer (modular)
    private let analyzer = CatchPhotoAnalyzer()

  // Scientist flow manager (nil for non-scientist roles)
  @Published var scientistFlow: ScientistCatchFlowManager?

  // Simple dialog flow
  private enum Step {
    case idle
    case reviewAnalysis   // analysis shown, user may edit or go to memo
    case scientistFlow    // delegates to ScientistCatchFlowManager
    case offerVoiceMemo   // (kept for possible future use)
    case complete
  }

  private var step: Step = .idle

  /// Whether the current user is a scientist (checked once at photo analysis time).
  private var isScientistRole: Bool {
    AuthService.shared.currentUserType == .scientist
  }

  // MARK: - Context updates

  func updateGuideContext(guide: String) {
    guideName = guide == "Guide" ? "" : guide
  }

  func updateAnglerContext(angler: String) {
    currentAnglerName = (angler == "Select" ? "" : angler)
  }

  func updateTripContext(trip: String) {
    // reserved for future contextual prompts
  }

  func updateLocation(_ location: CLLocation?) {
    currentLocation = location
  }

  // MARK: - Conversation start (triggered by angler selection)

  func startConversationIfNeeded() {
    guard messages.isEmpty else { return }

    let guidePart = guideName.isEmpty ? "" : "\(guideName), "

    // No angler name here; simple guide-focused intro
    appendAssistant("Hi \(guidePart)upload a photo of the fish")

    // Let UI show the photo button inline with this message
    showCaptureOptions = true
    step = .idle
  }

  /// Whether the chat should use the scientific visual style.
  var isScientistMode: Bool {
    isScientistRole
  }

    // MARK: - Photo analysis entry point

    func handlePhotoSelected(_ picked: PickedPhoto) {
      // 1. Decide which location to use: EXIF first, then whatever ReportChatView last gave us
      let bestLocation = picked.exifLocation ?? currentLocation

      // Remember this as the current location for later (logs, PicMemo snapshot, etc.)
      currentLocation = bestLocation

      // 2. Decide which timestamp to use: EXIF first, then "now"
      let bestDate = picked.exifDate ?? Date()
      currentPhotoDate = bestDate

      // 3. Show the image itself as a chat bubble from the user
      messages.append(ChatMessage(sender: .user, text: nil, image: picked.image))

      // 4. Persist the photo to disk via PhotoStore and remember filename
      if let filename = try? PhotoStore.shared.save(image: picked.image) {
        self.photoFilename = filename
      } else {
        self.photoFilename = nil
      }

      // 5. Clear any old buttons / analysis state from previous catches
      confirmAnalysisMessageID = nil
      voiceMemoAnchorMessageID = nil
      initialAnalysis = nil
      currentAnalysis = nil

      // 6. We're now analyzing – show typing indicator
      isAssistantTyping = true

      Task {
        // Artificial pause so user sees "thinking" state
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

          let analysis = await analyzer.analyze(
            image: picked.image,
            location: bestLocation
          )

        await MainActor.run {
          self.isAssistantTyping = false
          self.currentAnalysis = analysis

          // Capture the very first analysis as the "initial" snapshot.
          if self.initialAnalysis == nil {
            self.initialAnalysis = analysis
          }

          if self.isScientistRole {
            self.beginScientistFlow(analysis: analysis)
          } else {
            self.beginStandardFlow(analysis: analysis)
          }
        }
      }
    }

  // MARK: - Flow branching

  private func beginStandardFlow(analysis: CatchPhotoAnalysis) {
    step = .reviewAnalysis

    let summary = formattedSummary(from: analysis)

    let anglerPart: String = currentAnglerName.isEmpty
      ? "your angler"
      : currentAnglerName

    appendAssistant("""
    Here's what I see in the photo for \(anglerPart):
    \(summary)
    """)

    let prompt = appendAssistant(
      "Let me know any changes, or you can record a memo using the mic — or record later."
    )
    voiceMemoAnchorMessageID = prompt.id
    confirmAnalysisMessageID = nil
  }

  private func beginScientistFlow(analysis: CatchPhotoAnalysis) {
    step = .scientistFlow

    // Parse species/stage from analysis
    let (speciesName, stage) = splitSpecies(analysis.species)
    let sexValue = stripLeadingLabel(analysis.sex, label: "sex")
    let prettySexValue = prettySex(sexValue)

    // Extract numeric length
    let rawLen = cleanedField(analysis.estimatedLength ?? "")
    let lengthValue: Double? = extractLengthInches(from: rawLen).map(Double.init)

    // Create and initialize the scientist flow manager
    let flow = ScientistCatchFlowManager()
    flow.initialize(
      species: speciesName.isEmpty || speciesName == "-" ? nil : speciesName,
      lifecycleStage: stage,
      sex: prettySexValue.isEmpty ? nil : prettySexValue,
      lengthInches: lengthValue,
      riverName: cleanedField(analysis.riverName ?? "")
    )
    scientistFlow = flow

    // Build location line for context
    let locationLine: String
    let cleanedRiver = cleanedField(analysis.riverName ?? "")
    if !cleanedRiver.isEmpty
        && !cleanedRiver.hasPrefix("No river detected for")
        && !cleanedRiver.hasPrefix("No rivers configured for") {
      locationLine = "Location: \(cleanedRiver)"
    } else if let loc = currentLocation {
      locationLine = String(format: "Location: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
    } else {
      locationLine = "Location: No GPS coordinates available"
    }

    // Step 1: Show identification only (species, lifecycle, sex) — no measurements yet.
    // Measurements will be shown after species/sex are confirmed.
    let identificationText = flow.identificationSummary()

    let msg = appendAssistant("""
    Here's what I identified:
    \(locationLine)
    \(identificationText)

    Confirm the species and sex, or type corrections.
    """)

    flow.confirmAnchorID = msg.id
  }

  // MARK: - Scientist flow actions (called from CatchChatView)

  /// Scientist confirms the current step.
  func scientistConfirm() {
    guard let flow = scientistFlow else { return }

    // If confirming identification and species was corrected, re-estimate length
    // using the corrected species before advancing to measurements.
    if flow.currentStep == .identification && flow.speciesWasCorrected {
      reEstimateLengthForCorrectedSpecies(flow: flow)
    }

    flow.confirmAnchorID = nil

    let nextMessage = flow.confirm()

    if flow.currentStep == .voiceMemo {
      // Show voice memo buttons
      let msg = appendAssistant(nextMessage)
      voiceMemoAnchorMessageID = msg.id
      confirmAnalysisMessageID = nil
    } else if flow.currentStep == .complete {
      // Trigger save
      triggerSave()
    } else {
      // Show next step (Next button for intermediate steps, Confirm for final summary)
      let msg = appendAssistant(nextMessage)
      flow.confirmAnchorID = msg.id
    }
  }

  /// Scientist edits the current step value via text input.
  func scientistApplyEdit(_ text: String) {
    guard let flow = scientistFlow else { return }

    flow.confirmAnchorID = nil

    let (updatedPrompt, autoAdvanced) = flow.applyEdit(text)

    if autoAdvanced {
      // Value entry auto-confirmed the step and advanced
      if flow.currentStep == .finalSummary {
        // Show final analysis with Confirm button
        let msg = appendAssistant(updatedPrompt)
        flow.confirmAnchorID = msg.id
      } else {
        let msg = appendAssistant(updatedPrompt)
        flow.confirmAnchorID = msg.id
      }
    } else {
      let msg = appendAssistant("Got it, updated:\n\(updatedPrompt)")
      flow.confirmAnchorID = msg.id
    }
  }

  /// Scientist skips voice memo from the voice memo step.
  func scientistSkipVoiceMemo() {
    guard let flow = scientistFlow else { return }

    voiceMemoAnchorMessageID = nil
    flow.currentStep = .complete

    // Show final summary then save
    let summaryText = flow.finalSummaryText()
    appendAssistant(summaryText)
    appendAssistant("Saving catch now...")
    triggerSave()
  }

  /// Re-estimate length when the scientist corrects the species during identification.
  /// The regressor uses species index as an input feature, and some species (e.g. sea_run_trout)
  /// bypass the regressor entirely. Changing species can dramatically affect the length estimate.
  private func reEstimateLengthForCorrectedSpecies(flow: ScientistCatchFlowManager) {
    guard let fv = initialAnalysis?.featureVector else {
      AppLogging.log("reEstimateLength: no feature vector available, keeping original length", level: .warn, category: .ml)
      return
    }

    let result = analyzer.reEstimateLength(
      originalFV: fv,
      correctedSpecies: flow.species,
      correctedLifecycleStage: flow.lifecycleStage
    )

    if let newLength = result.lengthInches {
      let oldLength = flow.lengthInches
      flow.lengthInches = newLength
      flow.lengthSource = result.source
      AppLogging.log({
        "Species corrected: re-estimated length from \(oldLength.map { String(format: "%.1f", $0) } ?? "nil") " +
        "to \(String(format: "%.1f", newLength)) inches (source: \(result.source.rawValue))"
      }, level: .info, category: .ml)
    }
  }

  // MARK: - Sending user messages

  func sendCurrentInput() {
    let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    messages.append(ChatMessage(sender: .user, text: trimmed, image: nil))
    userInput = ""
    handleUserResponse(trimmed)
  }

  // MARK: - Dialog policy

  private func handleUserResponse(_ text: String) {
    let lower = text.lowercased()

    // Global "save" command (still supported)
    if lower == "save" || lower == "save catch" || lower == "save this" {
      triggerSave()
      return
    }

    switch step {
    case .scientistFlow:
      // In scientist flow, user text is treated as an edit for the current step
      scientistApplyEdit(text)

    case .reviewAnalysis:
      // Any user text is treated as corrections (including bare numbers like "38").
      applyCorrections(from: text)
      let updated = formattedSummary(from: currentAnalysis)
      appendAssistant(
        "Got it, I've updated the details to:\n\(updated)"
      )

      if confirmAnalysisMessageID != nil {
        let confirmMsg = appendAssistant(
          "If this looks good, tap Confirm to save this catch."
        )
        confirmAnalysisMessageID = confirmMsg.id
        voiceMemoAnchorMessageID = nil
      } else {
        let prompt = appendAssistant(
          "Let me know any other changes, or you can record a memo using the mic — or record later."
        )
        voiceMemoAnchorMessageID = prompt.id
        confirmAnalysisMessageID = nil
      }

    case .offerVoiceMemo:
      appendAssistant(
        "Whenever you're ready, tap the Voice memo button to record the catch description, or keep chatting to add more details."
      )

    case .idle, .complete:
      appendAssistant("You can upload another photo, record a voice memo, or tell me more about the catch here.")
    }
  }

  // Called from the Confirm button in the UI (final save)
  func confirmAnalysisFromButton() {
    guard currentAnalysis != nil else { return }

    confirmAnalysisMessageID = nil
    triggerSave()
  }

  // Called from the UI if needed
  func triggerSave() {
    performSave()
  }

  // MARK: - Voice memo decision (now vs later)

  /// Call this from the "Record later" icon/button anchored to `voiceMemoAnchorMessageID`.
  func deferVoiceMemoToLater() {
    let finalSummary = formattedSummary(from: currentAnalysis)

    appendAssistant(
      "No problem, you can always record a memo for this catch later. I'll go ahead and prepare the summary now."
    )

    appendAssistant("Here's the summary I'll use:\n\(finalSummary)")

    let confirmMsg = appendAssistant("If this looks good, tap Confirm to save this catch.")
    confirmAnalysisMessageID = confirmMsg.id

    // We're done with the memo prompt
    voiceMemoAnchorMessageID = nil
  }

  // MARK: - Helpers

  @discardableResult
  private func appendAssistant(_ text: String) -> ChatMessage {
    let msg = ChatMessage(sender: .assistant, text: text, image: nil)
    messages.append(msg)
    return msg
  }

  private func cleanedField(_ s: String) -> String {
    var t = s
    let junk = [
      "(model)",
      "(needs custom model)",
      "(estimate)",
      "(photo estimate)"
    ]
    for token in junk {
      t = t.replacingOccurrences(of: token, with: "")
    }
    while t.contains("  ") {
      t = t.replacingOccurrences(of: "  ", with: " ")
    }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func stripLeadingLabel(_ raw: String?, label: String) -> String {
    guard let raw else { return "" }
    let cleaned = cleanedField(raw)
    let lower = cleaned.lowercased()

    guard lower.hasPrefix(label.lowercased()) else {
      return cleaned
    }

    var remainder = cleaned.dropFirst(label.count)
    while let first = remainder.first,
          first == ":" || first == " " {
      remainder = remainder.dropFirst()
    }

    return String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func prettySex(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower == "male" || lower == "female" {
      return raw.capitalized
    }
    return raw
  }

  /// Maps internal model labels to user-facing species names.
  /// Keys must match the lowercased, underscore-stripped output of `speciesLabels`
  /// in `CatchPhotoAnalyzer.swift`. When adding a species, update both in lockstep
  /// (see the `/new-species` slash command in `.claude/commands/`).
  private static let speciesDisplayNames: [String: String] = [
    "sea run trout": "Sea-Run Trout",
    "steelhead": "Steelhead",
  ]

  private func splitSpecies(_ raw: String?) -> (species: String, stage: String?) {
    let valueOnly = stripLeadingLabel(raw, label: "species")
    if valueOnly.isEmpty { return ("-", nil) }

    // Check if the value is the "unable to detect" sentinel
    if valueOnly.lowercased().contains("unable to") {
      return (valueOnly, nil)
    }

    let parts = valueOnly.split(separator: " ").map { String($0) }

    // Only "holding" and "traveler" are valid lifecycle stages.
    // If the last word is one of these, split it off; otherwise the entire string is the species.
    let lifecycleKeywords = ["holding", "traveler"]
    if let lastWord = parts.last, lifecycleKeywords.contains(lastWord.lowercased()) {
      let speciesParts = parts.dropLast()
      let speciesRaw = speciesParts.map { $0.lowercased() }.joined(separator: " ")
      let species = Self.speciesDisplayNames[speciesRaw]
        ?? speciesParts.map { $0.capitalized }.joined(separator: " ")
      let stage = lastWord.capitalized
      return (species.isEmpty ? "-" : species, stage)
    }

    // No lifecycle stage — look up the full string as a display name
    let speciesRaw = parts.map { $0.lowercased() }.joined(separator: " ")
    let species = Self.speciesDisplayNames[speciesRaw]
      ?? valueOnly.capitalized
    return (species, nil)
  }

  private func averagedLength(from raw: String) -> String {
    var cleaned = raw
      .replacingOccurrences(of: "inches", with: "")
      .replacingOccurrences(of: "inch", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if cleaned.isEmpty || cleaned == "-" {
      return cleaned
    }

    cleaned = cleaned.replacingOccurrences(of: " ", with: "")

    let separators: [Character] = ["–", "-", "—"]

    for sep in separators {
      if cleaned.contains(sep) {
        let parts = cleaned.split(separator: sep)
        if parts.count == 2,
           let a = Double(parts[0]),
           let b = Double(parts[1]) {
          let high = max(a, b)
          if high.rounded() == high {
            return "\(Int(high)) inches"
          } else {
            return String(format: "%.1f inches", high)
          }
        }
      }
    }

    if cleaned.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
      if let value = Double(cleaned) {
        if value.rounded() == value {
          return "\(Int(value)) inches"
        } else {
          return String(format: "%.1f inches", value)
        }
      }
    }

    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func formattedSummary(from analysis: CatchPhotoAnalysis?) -> String {
    guard let a = analysis else { return "No details yet." }

    var parts: [String] = []

      let cleaned = cleanedField(a.riverName ?? "")

      if !cleaned.isEmpty
          && !cleaned.hasPrefix("No river detected for")
          && !cleaned.hasPrefix("No rivers configured for") {
        // Normal case: show the matched river / water body name
        parts.append("Location: \(cleaned)")
      } else if let loc = currentLocation {
        // No river match — show raw GPS coordinates
        parts.append(String(
          format: "Location: %.4f, %.4f",
          loc.coordinate.latitude,
          loc.coordinate.longitude
        ))
      } else {
        parts.append("Location: No GPS coordinates available")
      }

    let (species, stage) = splitSpecies(a.species)
    if !species.isEmpty, species != "-" {
      parts.append("Species: \(species)")
    }
    if let stage, !stage.isEmpty {
      parts.append("Lifecycle stage: \(stage)")
    }

    let sexValueRaw = stripLeadingLabel(a.sex, label: "sex")
    if !sexValueRaw.isEmpty {
      let pretty = prettySex(sexValueRaw)
      parts.append("Sex: \(pretty)")
    }

    if let lengthRaw = a.estimatedLength {
      let cleanedLen = cleanedField(lengthRaw)
      let lower = cleanedLen.lowercased()
      if lower.contains("not available") {
        parts.append("Estimated length: Inconclusive, please manually enter in the chat below")
      } else {
        let avgLen = averagedLength(from: cleanedLen)
        if !avgLen.isEmpty {
          parts.append("Estimated length: \(avgLen)")
        }
      }
    }

    // Include girth/weight for scientist flow
    if let flow = scientistFlow {
      if let g = flow.girthInches {
        let prefix = flow.girthIsEstimated ? "~" : ""
        parts.append("Estimated girth: \(prefix)\(String(format: "%.1f inches", g))")
      }
      if let w = flow.weightLbs {
        let prefix = flow.weightIsEstimated ? "~" : ""
        parts.append("Estimated weight: \(prefix)\(String(format: "%.1f lbs", w))")
      }
    }

    return parts.isEmpty ? "No details yet." : parts.joined(separator: "\n")
  }

  private func applyCorrections(from text: String) {
    guard var analysis = currentAnalysis else {
      currentAnalysis = CatchPhotoAnalysis(
        riverName: nil,
        species: nil,
        sex: nil,
        estimatedLength: nil
      )
      return
    }

    let lower = text.lowercased()

    func value(after keyword: String) -> String? {
      guard let range = lower.range(of: keyword) else { return nil }
      let tail = text[range.upperBound...]
      if let isRange = tail.range(of: " is ") {
        return String(tail[isRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
      } else if let colonRange = tail.range(of: ":") {
        return String(tail[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // River corrections
    if let river = value(after: "river") {
      analysis = CatchPhotoAnalysis(
        riverName: river,
        species: analysis.species,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength,
        featureVector: analysis.featureVector,
        lengthSource: analysis.lengthSource
      )
    }

    // Species corrections
    if let species = value(after: "species") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: species,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength,
        featureVector: analysis.featureVector,
        lengthSource: analysis.lengthSource
      )
    }

    // Lifecycle stage corrections (explicit or inferred)
    if let stage = value(after: "lifecycle stage") ?? value(after: "stage") {
      // Store lifecycle stage by appending to species field as per splitSpecies format
      // If species already includes a stage, replace it with the corrected one.
      let currentSpecies = stripLeadingLabel(analysis.species, label: "species")
      let baseSpecies = currentSpecies.split(separator: " ").first.map(String.init) ?? currentSpecies
      let cleanedStage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: baseSpecies.isEmpty ? cleanedStage : baseSpecies + " " + cleanedStage,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength,
        featureVector: analysis.featureVector,
        lengthSource: analysis.lengthSource
      )
    } else {
      // If the user typed a single token that looks like a lifecycle stage, accept it.
      // Known examples: Traveler, Holding, Spawning, Kelt, Smolt, Resident
      let tokens = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split { !$0.isLetter }
        .map(String.init)

      if tokens.count == 1 {
        let candidate = tokens[0]
        let knownStages = ["traveler", "holding", "spawning", "kelt", "smolt", "resident"]
        if knownStages.contains(candidate.lowercased()) {
          let currentSpecies = stripLeadingLabel(analysis.species, label: "species")
          let baseSpecies = currentSpecies.split(separator: " ").first.map(String.init) ?? currentSpecies
          let cleanedStage = candidate
          analysis = CatchPhotoAnalysis(
            riverName: analysis.riverName,
            species: baseSpecies.isEmpty ? cleanedStage : baseSpecies + " " + cleanedStage,
            sex: analysis.sex,
            estimatedLength: analysis.estimatedLength,
            featureVector: analysis.featureVector,
            lengthSource: analysis.lengthSource
          )
        }
      }
    }

    // Sex corrections – explicit or inferred
    if let sexExplicit = value(after: "sex") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: sexExplicit,
        estimatedLength: analysis.estimatedLength,
        featureVector: analysis.featureVector,
        lengthSource: analysis.lengthSource
      )
    } else if let inferredSex = inferSex(from: text) {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: inferredSex,
        estimatedLength: analysis.estimatedLength,
        featureVector: analysis.featureVector,
        lengthSource: analysis.lengthSource
      )
    }

    // Length corrections from phrases ("length is 32")
    if let length = value(after: "length") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: analysis.sex,
        estimatedLength: length,
        featureVector: analysis.featureVector,
        lengthSource: .manual
      )
    } else {
      // Pure number input ("32", "32.5") → treat as new length in inches
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

              if let range = trimmed.range(of: #"(\d+(\.\d+)?)"#, options: .regularExpression) {
                let numberString = String(trimmed[range])
                analysis = CatchPhotoAnalysis(
                  riverName: analysis.riverName,
                  species: analysis.species,
                  sex: analysis.sex,
                  estimatedLength: "\(numberString) inches",
                  featureVector: analysis.featureVector,
                  lengthSource: .manual
        )
      }
    }

    currentAnalysis = analysis
  }

  private func inferSex(from text: String) -> String? {
    let tokens = text
      .lowercased()
      .split { !$0.isLetter }
      .map(String.init)

    if tokens.contains("male") { return "male" }
    if tokens.contains("female") { return "female" }
    if tokens.contains("hen") { return "hen" }
    if tokens.contains("buck") { return "buck" }

    return nil
  }

  // MARK: - Save command

  private func performSave() {
    var lines: [String] = []

    lines.append("Guide: \(guideName.isEmpty ? "-" : guideName)")
    lines.append("Angler: \(currentAnglerName.isEmpty ? "-" : currentAnglerName)")

    if let a = currentAnalysis {
      let rawRiver = cleanedField(a.riverName ?? "")
      let saveRiver = rawRiver.isEmpty ? "Unable to Detect via GPS" : rawRiver
      let (species, stage) = splitSpecies(a.species)
      let sexValueRaw = stripLeadingLabel(a.sex, label: "sex")
      let prettySexValue = prettySex(sexValueRaw)
      let rawLen = cleanedField(a.estimatedLength ?? "-")

      let length: String = if rawLen.lowercased().contains("not available") {
        "-"
      } else {
        averagedLength(from: rawLen)
      }

      lines.append("River: \(saveRiver)")
      lines.append("Species: \(species.isEmpty ? "-" : species)")
      lines.append("Lifecycle stage: \(stage ?? "-")")
      lines.append("Sex: \(prettySexValue.isEmpty ? "-" : prettySexValue)")
      lines.append("Estimated length: \(length.isEmpty ? "-" : length)")

      // Include girth/weight for scientist flow
      if let flow = scientistFlow {
        if let g = flow.girthInches {
          let prefix = flow.girthIsEstimated ? "~" : ""
          lines.append("Estimated girth: \(prefix)\(String(format: "%.1f inches", g))")
        }
        if let w = flow.weightLbs {
          let prefix = flow.weightIsEstimated ? "~" : ""
          lines.append("Estimated weight: \(prefix)\(String(format: "%.1f lbs", w))")
        }
      }
    } else {
      lines.append("River: -")
      lines.append("Species: -")
      lines.append("Lifecycle stage: -")
      lines.append("Sex: -")
      lines.append("Estimated length: -")
    }

    if let loc = currentLocation {
      lines.append(String(
        format: "Location: %.5f, %.5f",
        loc.coordinate.latitude,
        loc.coordinate.longitude
      ))
    } else {
      lines.append("Location: -")
    }

    if let note = attachedVoiceNotes.last {
      lines.append("Voice memo: YES (id: \(note.id.uuidString))")
    } else {
      lines.append("Voice memo: NO")
    }

    let logText = lines.joined(separator: "\n")
    self.catchLog = logText

    AppLogging.log("================ CATCH LOG ================", level: .info, category: .catch)
    AppLogging.log({ logText }, level: .debug, category: .catch)
    AppLogging.log("===========================================", level: .info, category: .catch)

    appendAssistant(
      """
      Got it, here's the catch summary I'm saving:

      \(logText)

      Saving catch now…
      """
    )

    saveRequested = true
  }

  // MARK: - Voice note attachment

  func attachVoiceNote(_ note: LocalVoiceNote) {
    if let previous = attachedVoiceNotes.last {
      VoiceNoteStore.shared.delete(previous)
      attachedVoiceNotes.removeAll()
    }

    attachedVoiceNotes.append(note)

    Task { @MainActor in
      self.appendAssistant(
        "🎙 Voice memo recorded. You can also re-record later — I'll always use the latest version."
      )

      try? await Task.sleep(nanoseconds: 1_000_000_000)

      if let flow = self.scientistFlow {
        // Scientist flow: memo recorded → show final summary → save
        self.voiceMemoAnchorMessageID = nil
        flow.currentStep = .complete

        let summaryText = flow.finalSummaryText()
        self.appendAssistant(summaryText)
        self.appendAssistant("Saving catch now...")
        self.triggerSave()
      } else {
        // Standard flow: show summary → confirm button
        let finalSummary = self.formattedSummary(from: self.currentAnalysis)
        self.appendAssistant("Here's the final summary I'll use:\n\(finalSummary)")

        let confirmMsg = self.appendAssistant("If this looks good, tap Confirm to save this catch.")
        self.confirmAnalysisMessageID = confirmMsg.id
        self.voiceMemoAnchorMessageID = nil
      }
    }
  }

  // MARK: - PicMemo snapshot

  struct CatchPicMemoSnapshot {
    var guideName: String
    var anglerName: String

    var riverName: String?
    var species: String?
    var lifecycleStage: String?
    var sex: String?
    var lengthInches: Int?

    var latitude: Double?
    var longitude: Double?
    var voiceNoteId: UUID?
    var photoFilename: String?

    var initialRiverName: String?
    var initialSpecies: String?
    var initialLifecycleStage: String?
    var initialSex: String?
    var initialLengthInches: Int?

    /// JSON-encoded ML feature vector from initial analysis (26 features).
    var mlFeatureVector: Data?
    /// How the length was estimated: "regressor", "heuristic", or "manual".
    var lengthSource: String?
    /// Version of the LengthRegressor model that produced the estimate.
    var modelVersion: String?

    // Girth & weight estimation (scientist flow) — final confirmed values
    var girthInches: Double?
    var weightLbs: Double?
    var girthIsEstimated: Bool?
    var weightIsEstimated: Bool?
    var weightDivisor: Int?
    var weightDivisorSource: String?
    var girthRatio: Double?
    var girthRatioSource: String?

    // Initial measurement estimates (calculated with confirmed species, before user edits length/girth)
    var initialLengthForMeasurements: Double?
    var initialGirthInches: Double?
    var initialWeightLbs: Double?
    var initialGirthIsEstimated: Bool?
    var initialWeightIsEstimated: Bool?
    var initialWeightDivisor: Int?
    var initialWeightDivisorSource: String?
    var initialGirthRatio: Double?
    var initialGirthRatioSource: String?
  }

  func makePicMemoSnapshot() -> CatchPicMemoSnapshot? {
    guard let analysis = currentAnalysis else {
      return nil
    }

    let cleanedRiverRaw = cleanedField(analysis.riverName ?? "")
    let finalRiver = cleanedRiverRaw.isEmpty ? "Unable to Detect via GPS" : cleanedRiverRaw

    let (species, stage) = splitSpecies(analysis.species)
    let sexValueRaw = stripLeadingLabel(analysis.sex, label: "sex")
    let prettySexValue = prettySex(sexValueRaw)
    let rawLen = cleanedField(analysis.estimatedLength ?? "")

    let lengthInches = extractLengthInches(from: rawLen)

    let initRiver = cleanedField(initialAnalysis?.riverName ?? "")
    let (initSpecies, initStage) = splitSpecies(initialAnalysis?.species)
    let initSexRaw = stripLeadingLabel(initialAnalysis?.sex, label: "sex")
    let initPrettySex = prettySex(initSexRaw)
    let initRawLen = cleanedField(initialAnalysis?.estimatedLength ?? "")
    let initLengthInches = extractLengthInches(from: initRawLen)

    // Use scientist flow values if available (overrides ML-only analysis)
    let finalSpecies: String?
    let finalStage: String?
    let finalSex: String?
    let finalLength: Int?

    if let flow = scientistFlow {
      finalSpecies = flow.species
      finalStage = flow.lifecycleStage
      finalSex = flow.sex
      finalLength = flow.lengthInches.map { Int(round($0)) }
    } else {
      finalSpecies = species.isEmpty || species == "-" ? nil : species
      finalStage = stage
      finalSex = prettySexValue.isEmpty ? nil : prettySexValue
      finalLength = lengthInches
    }

    return CatchPicMemoSnapshot(
      guideName: guideName,
      anglerName: currentAnglerName,
      riverName: finalRiver,
      species: finalSpecies,
      lifecycleStage: finalStage,
      sex: finalSex,
      lengthInches: finalLength,
      latitude: currentLocation?.coordinate.latitude,
      longitude: currentLocation?.coordinate.longitude,
      voiceNoteId: attachedVoiceNotes.last?.id,
      photoFilename: photoFilename,
      initialRiverName: initRiver.isEmpty ? nil : initRiver,
      initialSpecies: initSpecies.isEmpty || initSpecies == "-" ? nil : initSpecies,
      initialLifecycleStage: initStage,
      initialSex: initPrettySex.isEmpty ? nil : initPrettySex,
      initialLengthInches: initLengthInches,
      mlFeatureVector: initialAnalysis?.featureVector.flatMap { try? JSONEncoder().encode($0) },
      lengthSource: scientistFlow?.lengthSource?.rawValue
        ?? (currentAnalysis?.lengthSource ?? initialAnalysis?.lengthSource)?.rawValue,
      modelVersion: initialAnalysis?.modelVersion,
      girthInches: scientistFlow?.girthInches,
      weightLbs: scientistFlow?.weightLbs,
      girthIsEstimated: scientistFlow?.girthIsEstimated,
      weightIsEstimated: scientistFlow?.weightIsEstimated,
      weightDivisor: scientistFlow?.divisor,
      weightDivisorSource: scientistFlow?.divisorSource,
      girthRatio: scientistFlow?.girthRatio,
      girthRatioSource: scientistFlow?.girthRatioSource,
      initialLengthForMeasurements: scientistFlow?.initialLengthForMeasurements,
      initialGirthInches: scientistFlow?.initialGirthInches,
      initialWeightLbs: scientistFlow?.initialWeightLbs,
      initialGirthIsEstimated: scientistFlow?.initialGirthIsEstimated,
      initialWeightIsEstimated: scientistFlow?.initialWeightIsEstimated,
      initialWeightDivisor: scientistFlow?.initialDivisor,
      initialWeightDivisorSource: scientistFlow?.initialDivisorSource,
      initialGirthRatio: scientistFlow?.initialGirthRatio,
      initialGirthRatioSource: scientistFlow?.initialGirthRatioSource
    )
  }

  private func extractLengthInches(from raw: String) -> Int? {
    if raw.isEmpty { return nil }

    let normalized = averagedLength(from: raw)
    let digits = normalized.filter { "0123456789.".contains($0) }
    guard !digits.isEmpty else { return nil }

    if let value = Double(digits) {
      return Int(round(value))
    }
    return nil
  }
}

#if canImport(UIKit)
extension UIApplication {
  func endEditing(_ force: Bool) {
    connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .endEditing(force)
  }
}
#endif
