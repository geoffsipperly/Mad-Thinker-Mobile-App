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

  /// The ID of the assistant message that the Upload button should anchor
  /// next to. Updated when the flow progresses from the head photo prompt to
  /// the primary fish photo prompt so the button "moves" with the chat.
  /// Nil means no explicit anchor — fall back to the first message when
  /// `showCaptureOptions == true`.
  @Published var uploadAnchorMessageID: UUID?

  // Voice notes attached to this catch (we currently keep the latest one only)
  @Published var attachedVoiceNotes: [LocalVoiceNote] = []

  // Show voice memo button next to a specific assistant message
  @Published var voiceMemoAnchorMessageID: UUID?

  // Save flow
  @Published var saveRequested: Bool = false
  @Published var catchLog: String?

  // Context from the header
  @Published private(set) var guideName: String = ""
  @Published private(set) var currentAnglerName: String = ""

  /// Whether this catch should be routed through the research-grade flow.
  /// Guides can opt in via the Conservation toggle on GuideLandingView.
  /// Researcher-role users always take the research flow regardless of this flag.
  /// Seeded by `ReportChatView` from `ConservationModeStore.shared` in `handleOnAppear`.
  @Published var conservationMode: Bool = false

    // Latest device location (from ReportChatView)
    private var currentLocation: CLLocation?

    // Best timestamp for the current photo (EXIF or fallback)
    private var currentPhotoDate: Date?

  // Expose best photo timestamp (read-only)
  public var photoTimestamp: Date? { currentPhotoDate }

  // Expose location for confirmation screen (read-only)
  public var currentLocationForDisplay: CLLocation? { currentLocation }

    // Latest analysis so we can update it from user corrections
    private var currentAnalysis: CatchPhotoAnalysis?

    // Initial analysis snapshot (before any user corrections)
    private var initialAnalysis: CatchPhotoAnalysis?

  // Saved photo filename (in PhotoStore)
  @Published var photoFilename: String?

  /// Filename of the close-up head photo, captured as the FIRST step of the
  /// conservation/research flow (before the primary fish photo). Nil outside
  /// of that flow or until the user uploads the head shot.
  @Published var headPhotoFilename: String?

  /// Filename of the head shot the user just uploaded but has not yet
  /// confirmed. Distinct from `headPhotoFilename` so a Retake can discard
  /// it without affecting any previously committed value. Promoted to
  /// `headPhotoFilename` on `confirmHeadPhoto()`.
  @Published var pendingHeadPhotoFilename: String?

  /// Anchor for the Confirm / Retake side buttons shown after a head photo
  /// is uploaded in the conservation/research flow. Nil outside that
  /// intermediate confirmation step.
  @Published var headConfirmAnchorMessageID: UUID?

  /// True when the chat is waiting for the user to upload the head photo
  /// before the regular fish-photo analysis pipeline runs. Only set in the
  /// conservation/research flow. Flipped off after the head photo is saved.
  @Published var awaitingHeadPhoto: Bool = false

  /// True when the researcher is choosing between recording a catch or observation.
  @Published var awaitingActivityChoice: Bool = false

  /// Anchor for the catch/observation choice buttons next to the initial prompt.
  var activityChoiceAnchorMessageID: UUID?

  /// Set to true by `chooseObservation()` so the view can present RecordObservationSheet.
  @Published var showRecordObservation: Bool = false

  // Photo analyzer (modular)
    private let analyzer = CatchPhotoAnalyzer()

  /// Step-by-step flow driver used by ALL roles. For guides with Conservation
  /// OFF, `flow.includeStudyAndSampleSteps == false` short-circuits the
  /// finalSummary → voiceMemo transition so they skip research-only steps.
  /// Nil until a photo is analyzed.
  @Published var researcherFlow: ResearcherCatchFlowManager?

  // High-level conversation state. Detailed step handling lives inside
  // ResearcherCatchFlowManager once a photo has been analyzed.
  private enum Step {
    case idle
    case researcherFlow    // delegates to ResearcherCatchFlowManager
  }

  private var step: Step = .idle

  /// Whether the current user is a researcher (checked once at photo analysis time).
  private var isResearcherRole: Bool {
    AuthService.shared.currentUserType == .researcher
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

  /// Reset all state so the researcher can record another catch from the same landing view.
  func resetForNewCatch() {
    messages = []
    userInput = ""
    isAssistantTyping = false
    showCaptureOptions = false
    attachedVoiceNotes = []
    voiceMemoAnchorMessageID = nil
    saveRequested = false
    catchLog = nil
    photoFilename = nil
    headPhotoFilename = nil
    pendingHeadPhotoFilename = nil
    headConfirmAnchorMessageID = nil
    awaitingHeadPhoto = false
    awaitingActivityChoice = false
    activityChoiceAnchorMessageID = nil
    showRecordObservation = false
    researcherFlow = nil
    currentAnalysis = nil
    initialAnalysis = nil
    currentPhotoDate = nil
    step = .idle
    startConversationIfNeeded()
  }

  func updateLocation(_ location: CLLocation?) {
    currentLocation = location
  }

  // MARK: - Conversation start (triggered by angler selection)

  func startConversationIfNeeded() {
    guard messages.isEmpty else { return }

    let namePart: String
    if isResearcherRole, let first = AuthService.shared.currentFirstName, !first.isEmpty {
      namePart = "\(first), "
    } else {
      namePart = guideName.isEmpty ? "" : "\(guideName), "
    }

    // Researchers get a choice between recording a catch or an observation.
    // Guides with Conservation ON go straight to the head-photo prompt.
    // Everyone else gets the regular fish photo prompt.
    let firstPrompt: ChatMessage
    if isResearcherRole {
      awaitingActivityChoice = true
      firstPrompt = appendAssistant("Hi \(namePart)you can record a catch or an observation.")
      activityChoiceAnchorMessageID = firstPrompt.id
      step = .idle
      return
    } else if conservationMode {
      awaitingHeadPhoto = true
      firstPrompt = appendAssistant("Hi \(namePart)let's start with a close-up photo of the fish's head.\n§\nThis photo will be used to uniquely identify the fish.")
    } else {
      firstPrompt = appendAssistant("Hi \(namePart)upload a photo of the fish")
    }

    // Anchor the Upload button to this first prompt. It will re-anchor to
    // the "now upload the full fish" prompt after the head photo is captured.
    uploadAnchorMessageID = firstPrompt.id
    showCaptureOptions = true
    step = .idle
  }

  /// Whether the chat should use the scientific visual style.
  var isResearcherMode: Bool {
    isResearcherRole
  }

  // MARK: - Activity choice (researcher only)

  /// Researcher tapped the catch (pencil) button — start the head-photo flow.
  func chooseCatch() {
    awaitingActivityChoice = false
    activityChoiceAnchorMessageID = nil

    awaitingHeadPhoto = true
    let prompt = appendAssistant("Let's get started with a photo of the fish's head.\n§\nThis photo will be used to uniquely identify the fish.")
    uploadAnchorMessageID = prompt.id
    showCaptureOptions = true
  }

  /// Researcher tapped the observation (microphone) button — signal the view
  /// to present RecordObservationSheet.
  func chooseObservation() {
    awaitingActivityChoice = false
    activityChoiceAnchorMessageID = nil
    showRecordObservation = true
  }

    // MARK: - Photo analysis entry point

    func handlePhotoSelected(_ picked: PickedPhoto) {
      // Conservation/research flow captures the HEAD photo first, before the
      // primary fish photo. Route this upload to the head-photo handler and
      // skip the ML analysis pipeline — we'll run analysis on the NEXT upload.
      if awaitingHeadPhoto {
        handleHeadPhotoSelected(picked)
        return
      }

      // 1. Decide which location to use: EXIF first, then whatever ReportChatView last gave us
      let bestLocation = picked.exifLocation ?? currentLocation

      // Remember this as the current location for later (logs, catch snapshot, etc.)
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

      // 5. Clear any old buttons / analysis state from previous catches.
      // The Upload button goes away now that the primary photo has been
      // captured; the flow takes over from here.
      voiceMemoAnchorMessageID = nil
      uploadAnchorMessageID = nil
      showCaptureOptions = false
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

          // All roles use the same step-by-step flow (identification → length
          // → girth → final summary → voice memo). Researchers and guides who
          // opted into Conservation additionally get the post-measurement
          // research steps (study participation, sample collection, barcode
          // scans). Guides with Conservation OFF jump straight from the final
          // summary to the voice memo offer.
          self.beginResearcherFlow(analysis: analysis)
        }
      }
    }

  /// Handles the close-up head photo uploaded as the first step of the
  /// conservation/research flow. Persists the image to PhotoStore as a
  /// *pending* filename and shows a Confirm / Retake prompt so the user can
  /// verify the shot before the chat advances to the full-body photo request.
  ///
  /// The ML analysis pipeline deliberately does NOT run on the head photo —
  /// analysis is for the full-body shot that drives species identification and
  /// length estimation. The head photo is metadata for research, stored
  /// alongside the catch and uploaded to the v5 `catch.headPhoto` field.
  ///
  /// `awaitingHeadPhoto` stays true until `confirmHeadPhoto()` is called, so a
  /// retake still routes through this handler rather than the analysis path.
  private func handleHeadPhotoSelected(_ picked: PickedPhoto) {
    // Show the image in the chat as user content.
    messages.append(ChatMessage(sender: .user, text: nil, image: picked.image))

    // Persist to the same CatchPhotos directory as the primary photo. This is
    // a *pending* file: if the user taps Retake we delete it via
    // PhotoStore.delete(filename:) before saving the replacement.
    if let filename = try? PhotoStore.shared.save(image: picked.image) {
      self.pendingHeadPhotoFilename = filename
    } else {
      self.pendingHeadPhotoFilename = nil
    }

    // Hide the Upload button while the user decides. It comes back anchored
    // to a different prompt on either Confirm or Retake.
    showCaptureOptions = false
    uploadAnchorMessageID = nil

    let confirmPrompt = appendAssistant("Tap Confirm to continue, or Retake to try again.")
    headConfirmAnchorMessageID = confirmPrompt.id
  }

  /// User confirmed the pending head photo. Promote the pending filename to
  /// the committed `headPhotoFilename` and advance the chat to the full-body
  /// fish photo prompt — this is the transition that `handleHeadPhotoSelected`
  /// used to perform inline before the confirmation step was added.
  func confirmHeadPhoto() {
    guard pendingHeadPhotoFilename != nil else { return }

    headPhotoFilename = pendingHeadPhotoFilename
    pendingHeadPhotoFilename = nil
    headConfirmAnchorMessageID = nil
    awaitingHeadPhoto = false

    let nextPrompt = appendAssistant("Got it. Please upload a photo of the full fish.\n§\nHold the fish with the head to the left for the best measurement analysis.")
    uploadAnchorMessageID = nextPrompt.id
    showCaptureOptions = true
  }

  /// User wants to retake the head photo. Discard the pending file and
  /// re-anchor the Upload button to a new prompt. We intentionally leave
  /// the previous photo bubble and "how does this look?" message in the
  /// chat log — consistent with the rest of this flow, which never rewrites
  /// history.
  func retakeHeadPhoto() {
    if let pending = pendingHeadPhotoFilename {
      PhotoStore.shared.delete(filename: pending)
    }
    pendingHeadPhotoFilename = nil
    headConfirmAnchorMessageID = nil
    // awaitingHeadPhoto stays true so the next upload still routes to
    // handleHeadPhotoSelected() rather than the analysis pipeline.

    let retakePrompt = appendAssistant("No problem — upload another close-up of the head.")
    uploadAnchorMessageID = retakePrompt.id
    showCaptureOptions = true
  }

  // MARK: - Flow branching

  private func beginResearcherFlow(analysis: CatchPhotoAnalysis) {
    step = .researcherFlow

    // Parse species/stage from analysis
    let (speciesName, stage) = splitSpecies(analysis.species)
    let sexValue = stripLeadingLabel(analysis.sex, label: "sex")
    let prettySexValue = prettySex(sexValue)

    // Extract numeric length
    let rawLen = cleanedField(analysis.estimatedLength ?? "")
    let lengthValue: Double? = extractLengthInches(from: rawLen).map(Double.init)

    // Create and initialize the researcher flow manager.
    //
    // Post-measurement research steps (study, sample, barcode scan) are only
    // included for researchers and for guides who opted into Conservation on
    // the landing view. Guides with Conservation OFF run identification →
    // length → girth → final summary → voice memo, skipping the extras.
    let flow = ResearcherCatchFlowManager()
    flow.includeStudyAndSampleSteps = isResearcherRole || conservationMode
    flow.initialize(
      species: speciesName.isEmpty || speciesName == "-" ? nil : speciesName,
      lifecycleStage: stage,
      sex: prettySexValue.isEmpty ? nil : prettySexValue,
      lengthInches: lengthValue,
      riverName: cleanedField(analysis.riverName ?? "")
    )
    researcherFlow = flow

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

  // MARK: - Researcher flow actions (called from CatchChatView)

  /// Researcher confirms the current step.
  func researcherConfirm() {
    guard let flow = researcherFlow else { return }

    // If confirming identification and species was corrected, re-estimate length
    // using the corrected species before advancing to measurements.
    if flow.currentStep == .identification && flow.speciesWasCorrected {
      reEstimateLengthForCorrectedSpecies(flow: flow)
    }

    flow.confirmAnchorID = nil

    let nextMessage = flow.confirm()

    if flow.currentStep == .voiceMemo {
      // Show voice memo buttons (Memo / Skip)
      let msg = appendAssistant(nextMessage)
      voiceMemoAnchorMessageID = msg.id
    } else if flow.currentStep == .complete {
      // Trigger save
      saveRequested = true
    } else if !nextMessage.isEmpty {
      let msg = appendAssistant(nextMessage)
      flow.confirmAnchorID = msg.id
    }
  }

  /// Researcher edits the current step value via text input.
  func researcherApplyEdit(_ text: String) {
    guard let flow = researcherFlow else { return }

    flow.confirmAnchorID = nil

    let (updatedPrompt, autoAdvanced, recognized) = flow.applyEdit(text)

    if !recognized {
      // Input was empty, profane, or unparseable — show the step's re-prompt
      // verbatim (no "Got it, updated:" prefix).
      let msg = appendAssistant(updatedPrompt)
      flow.confirmAnchorID = msg.id
      return
    }

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

  /// Researcher selects a study type (Pit, Floy, Radio Telemetry).
  func researcherSelectStudy(_ type: ResearcherCatchFlowManager.StudyType) {
    guard let flow = researcherFlow else { return }
    flow.confirmAnchorID = nil

    let (message, _) = flow.selectStudy(type)
    let msg = appendAssistant(message)
    flow.confirmAnchorID = msg.id
  }

  /// Researcher selects a sample type (Scale, Fin Tip, Both).
  func researcherSelectSample(_ type: ResearcherCatchFlowManager.SampleType) {
    guard let flow = researcherFlow else { return }
    flow.confirmAnchorID = nil

    let (message, _) = flow.selectSample(type)
    let msg = appendAssistant(message)
    flow.confirmAnchorID = msg.id
  }

  // Scale card and fin tip IDs are now entered manually through the chat
  // input bar (see ResearcherCatchFlowManager.applyEdit handling of
  // .scaleScan / .finTipScan). The old researcherScaleScan / researcherFinTipScan
  // methods — which generated mock "SCALE-1234" / "FINTIP-1234" values — have
  // been removed. Real barcode scanning is a follow-up.

  /// Researcher skips voice memo from the voice memo step.
  func researcherSkipVoiceMemo() {
    guard let flow = researcherFlow else { return }
    voiceMemoAnchorMessageID = nil
    flow.currentStep = .complete
    saveRequested = true
  }

  /// Re-estimate length when the researcher corrects the species during identification.
  /// The regressor uses species index as an input feature, and some species (e.g. sea_run_trout)
  /// bypass the regressor entirely. Changing species can dramatically affect the length estimate.
  private func reEstimateLengthForCorrectedSpecies(flow: ResearcherCatchFlowManager) {
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
    case .researcherFlow:
      // In the step-by-step flow, user text is treated as an edit for the
      // current step (identification / length / girth / etc.).
      researcherApplyEdit(text)

    case .idle:
      if ResearcherCatchFlowManager.containsProfanity(text) {
        appendAssistant("Let's keep it civil. You can upload another photo, record a voice memo, or tell me about the catch.")
      } else {
        appendAssistant("You can upload another photo, record a voice memo, or tell me more about the catch here.")
      }
    }
  }

  // Called from the UI if needed
  func triggerSave() {
    performSave()
  }

  // MARK: - Voice memo decision (now vs later)

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

    // Include girth/weight for researcher flow
    if let flow = researcherFlow {
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

  // MARK: - Save command

  private func performSave() {
    var lines: [String] = []

    if isResearcherRole {
      let first = AuthService.shared.currentFirstName ?? ""
      let last = AuthService.shared.currentLastName ?? ""
      let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
      lines.append("Researcher: \(full.isEmpty ? "-" : full)")
    } else {
      lines.append("Guide: \(guideName.isEmpty ? "-" : guideName)")
      lines.append("Angler: \(currentAnglerName.isEmpty ? "-" : currentAnglerName)")
    }

    // The flow holds the authoritative post-confirmation values (they reflect
    // any edits the user made to species, length, girth, etc.). currentAnalysis
    // is only used for fields the flow doesn't track, like river name.
    let rawRiver = cleanedField(currentAnalysis?.riverName ?? "")
    let saveRiver = rawRiver.isEmpty ? "Unable to Detect via GPS" : rawRiver
    lines.append("River: \(saveRiver)")

    if let flow = researcherFlow {
      lines.append("Species: \(flow.species?.isEmpty == false ? flow.species! : "-")")
      lines.append("Lifecycle stage: \(flow.lifecycleStage ?? "-")")
      lines.append("Sex: \(flow.sex?.isEmpty == false ? flow.sex! : "-")")
      if let l = flow.lengthInches {
        lines.append("Estimated length: \(String(format: "%.1f inches", l))")
      } else {
        lines.append("Estimated length: -")
      }
      if let g = flow.girthInches {
        let prefix = flow.girthIsEstimated ? "~" : ""
        lines.append("Estimated girth: \(prefix)\(String(format: "%.1f inches", g))")
      }
      if let w = flow.weightLbs {
        let prefix = flow.weightIsEstimated ? "~" : ""
        lines.append("Estimated weight: \(prefix)\(String(format: "%.1f lbs", w))")
      }
    } else {
      // Defensive — shouldn't happen now that every photo analysis creates a flow.
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

      // Every flow (guide + researcher, Conservation on or off) now runs
      // through ResearcherCatchFlowManager. A researcherFlow is always set by
      // the time a voice memo is attachable.
      guard let flow = self.researcherFlow else { return }
      self.voiceMemoAnchorMessageID = nil
      flow.currentStep = .complete

      let summaryText = flow.finalAnalysisText()
      self.appendAssistant(summaryText)
      self.appendAssistant("Saving catch now...")
      self.triggerSave()
    }
  }

  // MARK: - Catch snapshot

  struct CatchSnapshot {
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
    /// Filename of the close-up head shot captured in the conservation/research
    /// flow, if present. Maps to `CatchReport.headPhotoFilename` and the v5
    /// upload field `catch.headPhoto`.
    var headPhotoFilename: String?

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

    // Girth & weight estimation (researcher flow) — final confirmed values.
    // The "is estimated" flags live only on ResearcherCatchFlowManager; they're
    // deliberately not carried through the snapshot because they aren't
    // persisted or uploaded.
    var girthInches: Double?
    var weightLbs: Double?
    var weightDivisor: Int?
    var weightDivisorSource: String?
    var girthRatio: Double?
    var girthRatioSource: String?

    // Initial measurement estimates (calculated with confirmed species, before user edits length/girth)
    var initialLengthForMeasurements: Double?
    var initialGirthInches: Double?
    var initialWeightLbs: Double?
    var initialWeightDivisor: Int?
    var initialWeightDivisorSource: String?
    var initialGirthRatio: Double?
    var initialGirthRatioSource: String?

    /// Whether this catch participated in the conservation (research-grade) flow.
    /// True for researchers and for guides who toggled Conservation on.
    /// Maps to the v5 upload field `catch.conservationOptIn`.
    var conservationOptIn: Bool

    // Research tag / sample IDs — only populated when the researcher chose a
    // corresponding study or sample type during the post-measurement flow.
    // Map to the v5 upload fields of the same name.
    var floyId: String?
    var pitId: String?
    var scaleCardId: String?
    var dnaNumber: String?
  }

  func makeCatchSnapshot() -> CatchSnapshot? {
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

    // Use researcher flow values if available (overrides ML-only analysis)
    let finalSpecies: String?
    let finalStage: String?
    let finalSex: String?
    let finalLength: Int?

    if let flow = researcherFlow {
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

    return CatchSnapshot(
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
      headPhotoFilename: headPhotoFilename,
      initialRiverName: initRiver.isEmpty ? nil : initRiver,
      initialSpecies: initSpecies.isEmpty || initSpecies == "-" ? nil : initSpecies,
      initialLifecycleStage: initStage,
      initialSex: initPrettySex.isEmpty ? nil : initPrettySex,
      initialLengthInches: initLengthInches,
      mlFeatureVector: initialAnalysis?.featureVector.flatMap { try? JSONEncoder().encode($0) },
      lengthSource: researcherFlow?.lengthSource?.rawValue
        ?? (currentAnalysis?.lengthSource ?? initialAnalysis?.lengthSource)?.rawValue,
      modelVersion: initialAnalysis?.modelVersion,
      girthInches: researcherFlow?.girthInches,
      weightLbs: researcherFlow?.weightLbs,
      weightDivisor: researcherFlow?.divisor,
      weightDivisorSource: researcherFlow?.divisorSource,
      girthRatio: researcherFlow?.girthRatio,
      girthRatioSource: researcherFlow?.girthRatioSource,
      initialLengthForMeasurements: researcherFlow?.initialLengthForMeasurements,
      initialGirthInches: researcherFlow?.initialGirthInches,
      initialWeightLbs: researcherFlow?.initialWeightLbs,
      initialWeightDivisor: researcherFlow?.initialDivisor,
      initialWeightDivisorSource: researcherFlow?.initialDivisorSource,
      initialGirthRatio: researcherFlow?.initialGirthRatio,
      initialGirthRatioSource: researcherFlow?.initialGirthRatioSource,
      conservationOptIn: isResearcherRole || conservationMode,
      // Floy tag and scale card barcode are captured today by the existing
      // researcher flow. PIT and DNA fields ship in Phase 3.5 and stay nil
      // until then — leaving them as stubs avoids a second round of plumbing.
      floyId: researcherFlow?.floyTagNumber,
      pitId: nil,
      scaleCardId: researcherFlow?.scaleSampleBarcode,
      dnaNumber: nil
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
