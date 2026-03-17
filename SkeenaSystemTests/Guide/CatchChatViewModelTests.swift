import XCTest
@testable import SkeenaSystem

/// Tests for CatchChatViewModel's text-parsing helpers, correction logic,
/// formatted summary generation, and PicMemo snapshot creation.
///
/// Many helpers are private, so where necessary we replicate the logic
/// in test helpers (same pattern as CatchReportArchiveTests and
/// LengthEstimationTests) or exercise it through the public interface.
final class CatchChatViewModelTests: XCTestCase {

  // MARK: - Properties

  private var vm: CatchChatViewModel!

  override func setUp() {
    super.setUp()
    vm = CatchChatViewModel()
  }

  override func tearDown() {
    vm = nil
    super.tearDown()
  }

  // MARK: - Helpers (replicate private logic for direct unit testing)

  /// Replicates `CatchChatViewModel.cleanedField(_:)`
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

  /// Replicates `CatchChatViewModel.stripLeadingLabel(_:label:)`
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

  /// Replicates `CatchChatViewModel.prettySex(_:)`
  private func prettySex(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower == "male" || lower == "female" {
      return raw.capitalized
    }
    return raw
  }

  /// Replicates `CatchChatViewModel.splitSpecies(_:)`
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

  /// Replicates `CatchChatViewModel.averagedLength(from:)`
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

  /// Replicates `CatchChatViewModel.inferSex(from:)`
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

  /// Replicates `CatchChatViewModel.extractLengthInches(from:)`
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

  // MARK: - cleanedField Tests

  func testCleanedField_removesModelAnnotation() {
    XCTAssertEqual(cleanedField("Steelhead (model)"), "Steelhead")
  }

  func testCleanedField_removesEstimateAnnotation() {
    XCTAssertEqual(cleanedField("32-36 inches (estimate)"), "32-36 inches")
  }

  func testCleanedField_removesPhotoEstimateAnnotation() {
    XCTAssertEqual(cleanedField("32-36 inches (photo estimate)"), "32-36 inches")
  }

  func testCleanedField_removesNeedsCustomModel() {
    XCTAssertEqual(cleanedField("Unknown (needs custom model)"), "Unknown")
  }

  func testCleanedField_collapsesDoubleSpaces() {
    XCTAssertEqual(cleanedField("Steelhead  Traveler"), "Steelhead Traveler")
  }

  func testCleanedField_trimsWhitespace() {
    XCTAssertEqual(cleanedField("  Steelhead  "), "Steelhead")
  }

  func testCleanedField_emptyString_returnsEmpty() {
    XCTAssertEqual(cleanedField(""), "")
  }

  // MARK: - stripLeadingLabel Tests

  func testStripLeadingLabel_removesSpeciesLabel() {
    let result = stripLeadingLabel("Species: Steelhead", label: "species")
    XCTAssertEqual(result, "Steelhead")
  }

  func testStripLeadingLabel_caseInsensitive() {
    let result = stripLeadingLabel("SPECIES: Steelhead", label: "species")
    XCTAssertEqual(result, "Steelhead")
  }

  func testStripLeadingLabel_removesSexLabel() {
    let result = stripLeadingLabel("Sex: Male", label: "sex")
    XCTAssertEqual(result, "Male")
  }

  func testStripLeadingLabel_noMatchingLabel_returnsCleanedValue() {
    let result = stripLeadingLabel("Steelhead Traveler", label: "species")
    XCTAssertEqual(result, "Steelhead Traveler")
  }

  func testStripLeadingLabel_nilInput_returnsEmpty() {
    let result = stripLeadingLabel(nil, label: "species")
    XCTAssertEqual(result, "")
  }

  func testStripLeadingLabel_alsoRemovesModelAnnotation() {
    let result = stripLeadingLabel("Species (model): steelhead traveler", label: "species")
    XCTAssertEqual(result, "steelhead traveler")
  }

  // MARK: - prettySex Tests

  func testPrettySex_capitalizeMale() {
    XCTAssertEqual(prettySex("male"), "Male")
  }

  func testPrettySex_capitalizeFemale() {
    XCTAssertEqual(prettySex("female"), "Female")
  }

  func testPrettySex_alreadyCapitalized() {
    XCTAssertEqual(prettySex("Male"), "Male")
  }

  func testPrettySex_nonStandardPassesThrough() {
    XCTAssertEqual(prettySex("hen"), "hen")
    XCTAssertEqual(prettySex("buck"), "buck")
    XCTAssertEqual(prettySex("Unknown"), "Unknown")
  }

  // MARK: - splitSpecies Tests

  func testSplitSpecies_speciesAndStage() {
    let (species, stage) = splitSpecies("steelhead traveler")
    XCTAssertEqual(species, "Steelhead")
    XCTAssertEqual(stage, "Traveler")
  }

  func testSplitSpecies_singleWord() {
    let (species, stage) = splitSpecies("grayling")
    XCTAssertEqual(species, "Grayling")
    XCTAssertNil(stage)
  }

  func testSplitSpecies_nil_returnsDash() {
    let (species, stage) = splitSpecies(nil)
    XCTAssertEqual(species, "-")
    XCTAssertNil(stage)
  }

  func testSplitSpecies_empty_returnsDash() {
    let (species, stage) = splitSpecies("")
    XCTAssertEqual(species, "-")
    XCTAssertNil(stage)
  }

  func testSplitSpecies_withLabel_stripsLabel() {
    let (species, stage) = splitSpecies("Species (model): steelhead holding")
    XCTAssertEqual(species, "Steelhead")
    XCTAssertEqual(stage, "Holding")
  }

  func testSplitSpecies_multiWordStage() {
    let (species, stage) = splitSpecies("rainbow lake")
    XCTAssertEqual(species, "Rainbow")
    XCTAssertEqual(stage, "Lake")
  }

  // MARK: - averagedLength Tests

  func testAveragedLength_rangeWithHyphen_returnsHighEnd() {
    XCTAssertEqual(averagedLength(from: "32-36 inches"), "36 inches")
  }

  func testAveragedLength_rangeWithEnDash_returnsHighEnd() {
    XCTAssertEqual(averagedLength(from: "32–36 inches"), "36 inches")
  }

  func testAveragedLength_rangeWithEmDash_returnsHighEnd() {
    XCTAssertEqual(averagedLength(from: "32—36 inches"), "36 inches")
  }

  func testAveragedLength_singleInteger_returnsWithInches() {
    XCTAssertEqual(averagedLength(from: "36"), "36 inches")
  }

  func testAveragedLength_singleDecimal_returnsWithInches() {
    XCTAssertEqual(averagedLength(from: "32.5"), "32.5 inches")
  }

  func testAveragedLength_empty_returnsEmpty() {
    XCTAssertEqual(averagedLength(from: ""), "")
  }

  func testAveragedLength_dash_returnsDash() {
    XCTAssertEqual(averagedLength(from: "-"), "-")
  }

  func testAveragedLength_reversedRange_returnsMax() {
    XCTAssertEqual(averagedLength(from: "36-32 inches"), "36 inches")
  }

  func testAveragedLength_decimalRange_returnsHighEnd() {
    let result = averagedLength(from: "30.5-33.5 inches")
    XCTAssertEqual(result, "33.5 inches")
  }

  // MARK: - inferSex Tests

  func testInferSex_male() {
    XCTAssertEqual(inferSex(from: "It's a male fish"), "male")
  }

  func testInferSex_female() {
    XCTAssertEqual(inferSex(from: "This one is female"), "female")
  }

  func testInferSex_hen() {
    XCTAssertEqual(inferSex(from: "Nice hen"), "hen")
  }

  func testInferSex_buck() {
    XCTAssertEqual(inferSex(from: "Big buck"), "buck")
  }

  func testInferSex_noMatch_returnsNil() {
    XCTAssertNil(inferSex(from: "Nice fish"))
    XCTAssertNil(inferSex(from: "32 inches"))
    XCTAssertNil(inferSex(from: ""))
  }

  func testInferSex_maleTakesPrecedenceOverFemale() {
    // "male" is checked first in the function
    let result = inferSex(from: "male or female?")
    XCTAssertEqual(result, "male")
  }

  // MARK: - extractLengthInches Tests

  func testExtractLengthInches_simpleInteger() {
    XCTAssertEqual(extractLengthInches(from: "36 inches"), 36)
  }

  func testExtractLengthInches_decimalRounds() {
    XCTAssertEqual(extractLengthInches(from: "32.5 inches"), 33)
  }

  func testExtractLengthInches_rangeReturnsHighEnd() {
    XCTAssertEqual(extractLengthInches(from: "32-36 inches"), 36)
  }

  func testExtractLengthInches_empty_returnsNil() {
    XCTAssertNil(extractLengthInches(from: ""))
  }

  func testExtractLengthInches_dash_returnsNil() {
    XCTAssertNil(extractLengthInches(from: "-"))
  }

  func testExtractLengthInches_noDigits_returnsNil() {
    XCTAssertNil(extractLengthInches(from: "not available"))
  }

  // MARK: - Context Update Tests (public interface)

  func testUpdateGuideContext_guideDefault_becomesEmpty() {
    vm.updateGuideContext(guide: "Guide")
    XCTAssertEqual(vm.guideName, "")
  }

  func testUpdateGuideContext_realName_isPreserved() {
    vm.updateGuideContext(guide: "Mike Johnson")
    XCTAssertEqual(vm.guideName, "Mike Johnson")
  }

  func testUpdateAnglerContext_selectDefault_becomesEmpty() {
    vm.updateAnglerContext(angler: "Select")
    XCTAssertEqual(vm.currentAnglerName, "")
  }

  func testUpdateAnglerContext_realName_isPreserved() {
    vm.updateAnglerContext(angler: "John Doe")
    XCTAssertEqual(vm.currentAnglerName, "John Doe")
  }

  func testUpdateCommunity_setsValue() {
    vm.updateCommunity(communityID: "Bend Fly Shop")
    XCTAssertEqual(vm.communityID, "Bend Fly Shop")
  }

  func testUpdateCommunity_nil_clearsValue() {
    vm.updateCommunity(communityID: "Bend Fly Shop")
    vm.updateCommunity(communityID: nil)
    XCTAssertNil(vm.communityID)
  }

  // MARK: - makePicMemoSnapshot Tests (public interface)

  func testMakePicMemoSnapshot_noAnalysis_returnsNil() {
    XCTAssertNil(vm.makePicMemoSnapshot(), "Should return nil when no analysis has been performed")
  }

  // MARK: - startConversationIfNeeded Tests

  func testStartConversation_addsInitialMessage() {
    vm.startConversationIfNeeded()
    XCTAssertFalse(vm.messages.isEmpty, "Should have at least one message after starting conversation")
    XCTAssertTrue(vm.showCaptureOptions, "Should show capture options after conversation start")
  }

  func testStartConversation_idempotent() {
    vm.startConversationIfNeeded()
    let count = vm.messages.count
    vm.startConversationIfNeeded()
    XCTAssertEqual(vm.messages.count, count, "Starting conversation again should not add more messages")
  }

  func testStartConversation_includesGuideName() {
    vm.updateGuideContext(guide: "Mike")
    vm.startConversationIfNeeded()
    let text = vm.messages.first?.text ?? ""
    XCTAssertTrue(text.contains("Mike"), "First message should include guide name")
  }

  // MARK: - sendCurrentInput Tests (correction pipeline via public API)

  func testSendCurrentInput_emptyInput_doesNothing() {
    vm.startConversationIfNeeded()
    let count = vm.messages.count
    vm.userInput = "   "
    vm.sendCurrentInput()
    XCTAssertEqual(vm.messages.count, count, "Should not add messages for whitespace-only input")
  }

  // MARK: - Voice note attachment tests

  func testAttachedVoiceNotes_initiallyEmpty() {
    XCTAssertTrue(vm.attachedVoiceNotes.isEmpty, "Voice notes should be empty initially")
  }

  // MARK: - Initial state tests

  func testInitialState_isNotTyping() {
    XCTAssertFalse(vm.isAssistantTyping)
  }

  func testInitialState_messagesEmpty() {
    XCTAssertTrue(vm.messages.isEmpty)
  }

  func testInitialState_userInputEmpty() {
    XCTAssertEqual(vm.userInput, "")
  }

  func testInitialState_photoFilenameNil() {
    XCTAssertNil(vm.photoFilename)
  }

  func testInitialState_saveNotRequested() {
    XCTAssertFalse(vm.saveRequested)
  }

  func testInitialState_catchLogNil() {
    XCTAssertNil(vm.catchLog)
  }
}
