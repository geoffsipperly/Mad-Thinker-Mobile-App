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
  @Published private(set) var communityID: String?

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

  // Simple dialog flow
  private enum Step {
    case idle
    case reviewAnalysis // analysis shown, user may edit or go to memo
    case offerVoiceMemo // (kept for possible future use)
    case complete
  }

  private var step: Step = .idle

  // MARK: - Context updates

  func updateCommunity(communityID: String?) {
      self.communityID = communityID
    }

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

      // 6. We’re now analyzing – show typing indicator
      isAssistantTyping = true

      Task {
        // Artificial pause so user sees "thinking" state
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

          let analysis = await analyzer.analyze(
            image: picked.image,
            location: bestLocation,
            communityID: self.communityID
          )

        await MainActor.run {
          self.isAssistantTyping = false
          self.currentAnalysis = analysis

          // Capture the very first analysis as the "initial" snapshot.
          if self.initialAnalysis == nil {
            self.initialAnalysis = analysis
          }

          self.step = .reviewAnalysis

          let summary = self.formattedSummary(from: analysis)

          let anglerPart: String = self.currentAnglerName.isEmpty
            ? "your angler"
            : self.currentAnglerName

          // First message: the structured summary
          self.appendAssistant("""
          Here’s what I see in the photo for \(anglerPart):
          \(summary)
          """)

          // Second message: invite edits OR memo (Record / Later buttons)
          let prompt = self.appendAssistant(
            "Let me know any changes, or you can record a memo using the mic — or record later."
          )
          self.voiceMemoAnchorMessageID = prompt.id
          self.confirmAnalysisMessageID = nil
        }
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
    case .reviewAnalysis:
      // Any user text is treated as corrections (including bare numbers like "38").
      applyCorrections(from: text)
      let updated = formattedSummary(from: currentAnalysis)
      appendAssistant(
        "Got it, I’ve updated the details to:\n\(updated)"
      )

      // 🔑 Behavior split:
      // - If we've already shown Confirm before (confirmAnalysisMessageID != nil),
      //   keep the user in the "confirm" loop.
      // - If not, we’re still in the “memo or later” phase.
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
      "No problem, you can always record a memo for this catch later. I’ll go ahead and prepare the summary now."
    )

    appendAssistant("Here’s the summary I’ll use:\n\(finalSummary)")

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

  private func splitSpecies(_ raw: String?) -> (species: String, stage: String?) {
    let valueOnly = stripLeadingLabel(raw, label: "species")
    if valueOnly.isEmpty { return ("-", nil) }

    let parts = valueOnly.split(separator: " ").map { String($0) }

    guard parts.count > 1 else {
      return (valueOnly.capitalized, nil)
    }

    let species = parts[0].capitalized
    let stage = parts.dropFirst().joined(separator: " ").capitalized
    return (species, stage.isEmpty ? nil : stage)
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

      if cleaned.isEmpty {
        // No message from analyzer → fall back to generic text
        parts.append("River: Unable to Detect via GPS")
      } else if cleaned.hasPrefix("No river detected for")
                  || cleaned.hasPrefix("No rivers configured for") {
        // Our special messages for scenarios 2 and 3:
        // - "No river detected for <community>"
        // - "No rivers configured for <community>"
        // Use them verbatim so the user sees exactly that.
        parts.append(cleaned)
      } else {
        // Normal case: show the river name
        parts.append("River: \(cleaned)")
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
        estimatedLength: analysis.estimatedLength
      )
    }

    // Species corrections
    if let species = value(after: "species") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: species,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength
      )
    }

    // Lifecycle stage corrections (explicit or inferred)
    if let stage = value(after: "lifecycle stage") ?? value(after: "stage") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength
      )
      // Store lifecycle stage by appending to species field as per splitSpecies format
      // If species already includes a stage, replace it with the corrected one.
      let currentSpecies = stripLeadingLabel(analysis.species, label: "species")
      let baseSpecies = currentSpecies.split(separator: " ").first.map(String.init) ?? currentSpecies
      let cleanedStage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: baseSpecies.isEmpty ? cleanedStage : baseSpecies + " " + cleanedStage,
        sex: analysis.sex,
        estimatedLength: analysis.estimatedLength
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
            estimatedLength: analysis.estimatedLength
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
        estimatedLength: analysis.estimatedLength
      )
    } else if let inferredSex = inferSex(from: text) {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: inferredSex,
        estimatedLength: analysis.estimatedLength
      )
    }

    // Length corrections from phrases ("length is 32")
    if let length = value(after: "length") {
      analysis = CatchPhotoAnalysis(
        riverName: analysis.riverName,
        species: analysis.species,
        sex: analysis.sex,
        estimatedLength: length
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
                  estimatedLength: "\(numberString) inches"
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
      Got it, here’s the catch summary I’m saving:

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
        "🎙 Voice memo recorded. You can also re-record later — I’ll always use the latest version."
      )

      try? await Task.sleep(nanoseconds: 1_000_000_000)

      let finalSummary = self.formattedSummary(from: self.currentAnalysis)
      self.appendAssistant("Here’s the final summary I’ll use:\n\(finalSummary)")

      let confirmMsg = self.appendAssistant("If this looks good, tap Confirm to save this catch.")
      self.confirmAnalysisMessageID = confirmMsg.id
      self.voiceMemoAnchorMessageID = nil
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

    return CatchPicMemoSnapshot(
      guideName: guideName,
      anglerName: currentAnglerName,
      riverName: finalRiver,
      species: species.isEmpty || species == "-" ? nil : species,
      lifecycleStage: stage,
      sex: prettySexValue.isEmpty ? nil : prettySexValue,
      lengthInches: lengthInches,
      latitude: currentLocation?.coordinate.latitude,
      longitude: currentLocation?.coordinate.longitude,
      voiceNoteId: attachedVoiceNotes.last?.id,
      photoFilename: photoFilename,
      initialRiverName: initRiver.isEmpty ? nil : initRiver,
      initialSpecies: initSpecies.isEmpty || initSpecies == "-" ? nil : initSpecies,
      initialLifecycleStage: initStage,
      initialSex: initPrettySex.isEmpty ? nil : initPrettySex,
      initialLengthInches: initLengthInches
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
