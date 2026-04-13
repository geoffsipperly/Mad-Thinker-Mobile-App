import XCTest
@testable import SkeenaSystem

/// Unit tests for ResearcherCatchFlowManager's input validation:
/// profanity rejection, unparseable identification, non-numeric
/// length/girth handling, and the ≥3-letter species fallback threshold.
@MainActor
final class ResearcherCatchFlowManagerTests: XCTestCase {

  private var flow: ResearcherCatchFlowManager!

  override func setUp() {
    super.setUp()
    flow = ResearcherCatchFlowManager()
  }

  override func tearDown() {
    flow = nil
    super.tearDown()
  }

  /// Helper: initialize the flow with typical ML analysis values and land
  /// on the identification step, ready for applyEdit tests.
  private func initializeAtIdentification(
    species: String? = "Steelhead",
    length: Double? = 30
  ) {
    flow.initialize(
      species: species,
      lifecycleStage: nil,
      sex: nil,
      lengthInches: length,
      riverName: "Bulkley"
    )
    XCTAssertEqual(flow.currentStep, .identification)
  }

  /// Helper: advance past identification to the confirmLength step.
  private func advanceToConfirmLength(species: String? = "Steelhead", length: Double? = 30) {
    initializeAtIdentification(species: species, length: length)
    _ = flow.confirm() // identification → confirmLength
    XCTAssertEqual(flow.currentStep, .confirmLength)
  }

  /// Helper: advance past confirmLength to the confirmGirth step.
  private func advanceToConfirmGirth() {
    advanceToConfirmLength()
    _ = flow.confirm() // confirmLength → confirmGirth
    XCTAssertEqual(flow.currentStep, .confirmGirth)
  }

  /// Helper: advance to the floyTagID step via study selection.
  private func advanceToFloyTagID() {
    advanceToConfirmGirth()
    _ = flow.confirm() // confirmGirth → finalSummary
    XCTAssertEqual(flow.currentStep, .finalSummary)
    _ = flow.confirm() // finalSummary → studyParticipation
    XCTAssertEqual(flow.currentStep, .studyParticipation)
    _ = flow.selectStudy(.floy) // → floyTagID
    XCTAssertEqual(flow.currentStep, .floyTagID)
  }

  /// Helper: advance to the scaleScan step via sample selection.
  private func advanceToScaleScan() {
    advanceToConfirmGirth()
    _ = flow.confirm() // → finalSummary
    _ = flow.confirm() // → studyParticipation
    _ = flow.confirm() // skip study → sampleCollection
    XCTAssertEqual(flow.currentStep, .sampleCollection)
    _ = flow.selectSample(.scale) // → scaleScan
    XCTAssertEqual(flow.currentStep, .scaleScan)
  }

  /// Helper: advance to the finTipScan step via "Both" sample selection.
  private func advanceToFinTipScan() {
    advanceToConfirmGirth()
    _ = flow.confirm() // → finalSummary
    _ = flow.confirm() // → studyParticipation
    _ = flow.confirm() // skip study → sampleCollection
    _ = flow.selectSample(.both) // → scaleScan
    XCTAssertEqual(flow.currentStep, .scaleScan)
    // Enter a scale card ID and confirm to advance to finTipScan
    _ = flow.applyEdit("SC-001")
    _ = flow.confirm() // scaleScan (both) → finTipScan
    XCTAssertEqual(flow.currentStep, .finTipScan)
  }

  // MARK: - Profanity rejection per step

  func testProfanity_identification_rejected() {
    initializeAtIdentification()
    let originalSpecies = flow.species

    let result = flow.applyEdit("fuck this fish")

    XCTAssertFalse(result.recognized, "Profane input must be rejected")
    XCTAssertFalse(result.autoAdvance)
    XCTAssertEqual(flow.currentStep, .identification, "Step must not advance on profanity")
    XCTAssertEqual(flow.species, originalSpecies, "Species must not be mutated by profane input")
    XCTAssertTrue(result.message.contains("keep it civil"), "Rejection message must contain 'keep it civil'")
  }

  func testProfanity_confirmLength_rejected() {
    advanceToConfirmLength()
    let originalLength = flow.lengthInches

    let result = flow.applyEdit("shit 32")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .confirmLength)
    XCTAssertEqual(flow.lengthInches, originalLength, "Length must not be mutated by profane input")
    XCTAssertTrue(result.message.contains("keep it civil"))
  }

  func testProfanity_confirmGirth_rejected() {
    advanceToConfirmGirth()
    let originalGirth = flow.girthInches

    let result = flow.applyEdit("bullshit")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .confirmGirth)
    XCTAssertEqual(flow.girthInches, originalGirth)
    XCTAssertTrue(result.message.contains("keep it civil"))
  }

  func testProfanity_floyTagID_rejected() {
    advanceToFloyTagID()

    let result = flow.applyEdit("asshole")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .floyTagID)
    XCTAssertNil(flow.floyTagNumber, "Floy tag must not be set from profane input")
    XCTAssertTrue(result.message.contains("keep it civil"))
  }

  func testProfanity_scaleScan_rejected() {
    advanceToScaleScan()

    let result = flow.applyEdit("dick")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .scaleScan)
    XCTAssertNil(flow.scaleSampleBarcode)
    XCTAssertTrue(result.message.contains("keep it civil"))
  }

  func testProfanity_finTipScan_rejected() {
    advanceToFinTipScan()

    let result = flow.applyEdit("cunt")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .finTipScan)
    XCTAssertNil(flow.finTipSampleBarcode)
    XCTAssertTrue(result.message.contains("keep it civil"))
  }

  func testContainsProfanity_standaloneMatch() {
    XCTAssertTrue(ResearcherCatchFlowManager.containsProfanity("fuck"))
    XCTAssertTrue(ResearcherCatchFlowManager.containsProfanity("SHIT"))
    XCTAssertTrue(ResearcherCatchFlowManager.containsProfanity("What the fuck"))
  }

  func testContainsProfanity_punctuationSplit() {
    // "fuck!" splits into ["fuck"] — should match
    XCTAssertTrue(ResearcherCatchFlowManager.containsProfanity("fuck!"))
    // "f***ing" splits into ["f", "ing"] — should NOT match (partial tokens)
    XCTAssertFalse(ResearcherCatchFlowManager.containsProfanity("f***ing"))
  }

  func testContainsProfanity_cleanInput() {
    XCTAssertFalse(ResearcherCatchFlowManager.containsProfanity("Steelhead"))
    XCTAssertFalse(ResearcherCatchFlowManager.containsProfanity("rainbow trout female"))
    XCTAssertFalse(ResearcherCatchFlowManager.containsProfanity("32"))
    XCTAssertFalse(ResearcherCatchFlowManager.containsProfanity(""))
  }

  // MARK: - Unparseable identification

  func testIdentification_singleLetter_rejected() {
    initializeAtIdentification()
    let originalSpecies = flow.species

    let result = flow.applyEdit("x")

    XCTAssertFalse(result.recognized, "Single letter must be rejected")
    XCTAssertEqual(flow.species, originalSpecies, "Species must not change on single-letter input")
    XCTAssertTrue(result.message.contains("didn't catch that"))
  }

  func testIdentification_twoLetters_rejected() {
    initializeAtIdentification()
    let originalSpecies = flow.species

    let result = flow.applyEdit("xx")

    XCTAssertFalse(result.recognized, "Two-letter input must be rejected")
    XCTAssertEqual(flow.species, originalSpecies)
  }

  func testIdentification_emptyString_rejected() {
    initializeAtIdentification()

    let result = flow.applyEdit("")

    XCTAssertFalse(result.recognized, "Empty input must be rejected")
  }

  func testIdentification_whitespaceOnly_rejected() {
    initializeAtIdentification()

    let result = flow.applyEdit("   ")

    XCTAssertFalse(result.recognized, "Whitespace-only input must be rejected")
  }

  func testIdentification_knownSpecies_recognized() {
    initializeAtIdentification(species: nil)

    let result = flow.applyEdit("steelhead")

    XCTAssertTrue(result.recognized)
    XCTAssertEqual(flow.species, "Steelhead")
    XCTAssertEqual(flow.currentStep, .identification, "Identification stays until user confirms")
  }

  // MARK: - Non-numeric length/girth

  func testLength_pureText_rejected() {
    advanceToConfirmLength()

    let result = flow.applyEdit("big fish")

    XCTAssertFalse(result.recognized, "Non-numeric length must be rejected")
    XCTAssertEqual(flow.currentStep, .confirmLength, "Must stay on confirmLength")
    XCTAssertTrue(result.message.contains("didn't catch that"))
  }

  func testLength_validNumber_advances() {
    advanceToConfirmLength()

    let result = flow.applyEdit("32")

    XCTAssertTrue(result.recognized)
    XCTAssertTrue(result.autoAdvance)
    XCTAssertEqual(flow.currentStep, .confirmGirth)
    XCTAssertEqual(flow.lengthInches, 32)
  }

  func testLength_embeddedNumber_extracted() {
    advanceToConfirmLength()

    let result = flow.applyEdit("about 28 inches")

    XCTAssertTrue(result.recognized)
    XCTAssertTrue(result.autoAdvance)
    XCTAssertEqual(flow.lengthInches, 28)
    XCTAssertEqual(flow.currentStep, .confirmGirth)
  }

  func testGirth_pureText_rejected() {
    advanceToConfirmGirth()

    let result = flow.applyEdit("not sure")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.currentStep, .confirmGirth, "Must stay on confirmGirth")
    XCTAssertTrue(result.message.contains("didn't catch that"))
  }

  func testGirth_validNumber_advances() {
    advanceToConfirmGirth()

    let result = flow.applyEdit("14.5")

    XCTAssertTrue(result.recognized)
    XCTAssertTrue(result.autoAdvance)
    XCTAssertEqual(flow.currentStep, .finalSummary)
    XCTAssertEqual(flow.girthInches, 14.5)
    XCTAssertFalse(flow.girthIsEstimated, "User-entered girth must not be flagged as estimated")
  }

  func testGirth_embeddedNumber_extracted() {
    advanceToConfirmGirth()

    let result = flow.applyEdit("measured 15 inches")

    XCTAssertTrue(result.recognized)
    XCTAssertEqual(flow.girthInches, 15)
    XCTAssertEqual(flow.currentStep, .finalSummary)
  }

  // MARK: - ≥3-letter fallback threshold

  func testFallback_twoCharCandidate_rejected() {
    initializeAtIdentification(species: "Steelhead")
    let originalSpecies = flow.species

    // "ab" is 2 chars after stripping noise words — below threshold
    let result = flow.applyEdit("ab")

    XCTAssertFalse(result.recognized)
    XCTAssertEqual(flow.species, originalSpecies, "Species must not change for <3-char candidate")
  }

  func testFallback_threeCharCandidate_accepted() {
    initializeAtIdentification(species: nil)

    let result = flow.applyEdit("abc")

    XCTAssertTrue(result.recognized, "≥3-char unknown word must be accepted as species")
    XCTAssertEqual(flow.species, "abc")
  }

  func testFallback_noiseStrippedBelow3_sexStillRecognized() {
    // "male x" — species candidate after stripping "male" is "x" (1 char, rejected),
    // but sex = Male should still be recognized.
    initializeAtIdentification(species: "Steelhead")
    let originalSpecies = flow.species

    let result = flow.applyEdit("male x")

    XCTAssertTrue(result.recognized, "Sex keyword must still be recognized even if species candidate is too short")
    XCTAssertEqual(flow.sex, "Male")
    XCTAssertEqual(flow.species, originalSpecies, "Species must not change when leftover is <3 chars")
  }

  func testFallback_multiWordUnknown_accepted() {
    initializeAtIdentification(species: nil)

    let result = flow.applyEdit("tiger muskie")

    XCTAssertTrue(result.recognized)
    XCTAssertEqual(flow.species, "tiger muskie")
  }

  // MARK: - Happy-path step progression

  func testStepProgression_identificationThroughFinalSummary() {
    initializeAtIdentification()

    _ = flow.confirm() // identification → confirmLength
    XCTAssertEqual(flow.currentStep, .confirmLength)

    _ = flow.confirm() // confirmLength → confirmGirth (length was pre-set to 30)
    XCTAssertEqual(flow.currentStep, .confirmGirth)

    _ = flow.confirm() // confirmGirth → finalSummary
    XCTAssertEqual(flow.currentStep, .finalSummary)
  }

  func testApplyEdit_buttonDrivenStep_returnsNotRecognized() {
    advanceToConfirmGirth()
    _ = flow.confirm() // → finalSummary
    XCTAssertEqual(flow.currentStep, .finalSummary)

    let result = flow.applyEdit("some random text")

    XCTAssertFalse(result.recognized)
    XCTAssertTrue(result.message.contains("not expecting typed input"))
  }
}
