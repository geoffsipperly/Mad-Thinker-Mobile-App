import XCTest
@testable import SkeenaSystem

/// Tests for ReportFormViewModel validation logic, reset behavior,
/// and configuration properties.
///
/// Validates:
/// 1. `isValid` returns true only when all required fields are filled
/// 2. Hatchery origin requires a tag ID
/// 3. `reset()` clears transient fields but preserves defaults
/// 4. `lengths` range matches expected picker values
final class ReportFormViewModelTests: XCTestCase {

  // MARK: - Properties

  private var vm: ReportFormViewModel!

  override func setUp() {
    super.setUp()
    vm = ReportFormViewModel()
  }

  override func tearDown() {
    vm = nil
    super.tearDown()
  }

  // MARK: - Helpers

  /// Fills all required fields with valid values so `isValid` returns true.
  private func fillAllRequiredFields() {
    vm.river = "Nehalem"
    vm.species = "Steelhead"
    vm.sex = "Male"
    vm.origin = "Wild"
    vm.lengthInches = 32
    vm.quality = "Silver"
    vm.tactic = "Swinging"
    vm.guideName = "Mike Johnson"
    vm.clientName = "John Doe"
    vm.anglerNumber = "12345"
  }

  // MARK: - isValid: All fields filled

  func testIsValid_allFieldsFilled_returnsTrue() {
    fillAllRequiredFields()
    XCTAssertTrue(vm.isValid, "Should be valid when all required fields are filled")
  }

  // MARK: - isValid: Individual required field missing

  func testIsValid_emptyRiver_returnsFalse() {
    fillAllRequiredFields()
    vm.river = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when river is empty")
  }

  func testIsValid_whitespaceOnlyRiver_returnsFalse() {
    fillAllRequiredFields()
    vm.river = "   "
    XCTAssertFalse(vm.isValid, "Should be invalid when river is whitespace-only")
  }

  func testIsValid_emptySpecies_returnsFalse() {
    fillAllRequiredFields()
    vm.species = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when species is empty")
  }

  func testIsValid_emptySex_returnsFalse() {
    fillAllRequiredFields()
    vm.sex = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when sex is empty")
  }

  func testIsValid_emptyOrigin_returnsFalse() {
    fillAllRequiredFields()
    vm.origin = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when origin is empty")
  }

  func testIsValid_zeroLength_returnsFalse() {
    fillAllRequiredFields()
    vm.lengthInches = 0
    XCTAssertFalse(vm.isValid, "Should be invalid when lengthInches is 0")
  }

  func testIsValid_emptyQuality_returnsFalse() {
    fillAllRequiredFields()
    vm.quality = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when quality is empty")
  }

  func testIsValid_emptyTactic_returnsFalse() {
    fillAllRequiredFields()
    vm.tactic = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when tactic is empty")
  }

  func testIsValid_emptyGuideName_returnsFalse() {
    fillAllRequiredFields()
    vm.guideName = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when guideName is empty")
  }

  func testIsValid_emptyClientName_returnsFalse() {
    fillAllRequiredFields()
    vm.clientName = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when clientName is empty")
  }

  func testIsValid_emptyAnglerNumber_returnsFalse() {
    fillAllRequiredFields()
    vm.anglerNumber = ""
    XCTAssertFalse(vm.isValid, "Should be invalid when anglerNumber is empty")
  }

  func testIsValid_whitespaceOnlyAnglerNumber_returnsFalse() {
    fillAllRequiredFields()
    vm.anglerNumber = "   "
    XCTAssertFalse(vm.isValid, "Should be invalid when anglerNumber is whitespace-only")
  }

  // MARK: - isValid: Hatchery tag requirement

  func testIsValid_hatcheryOrigin_emptyTag_returnsFalse() {
    fillAllRequiredFields()
    vm.origin = "Hatchery"
    vm.tagId = ""
    XCTAssertFalse(vm.isValid, "Hatchery origin should require a tag ID")
  }

  func testIsValid_hatcheryOrigin_whitespaceTag_returnsFalse() {
    fillAllRequiredFields()
    vm.origin = "Hatchery"
    vm.tagId = "   "
    XCTAssertFalse(vm.isValid, "Hatchery origin should require non-whitespace tag ID")
  }

  func testIsValid_hatcheryOrigin_withTag_returnsTrue() {
    fillAllRequiredFields()
    vm.origin = "Hatchery"
    vm.tagId = "HT-001"
    XCTAssertTrue(vm.isValid, "Hatchery origin with tag should be valid")
  }

  func testIsValid_wildOrigin_emptyTag_returnsTrue() {
    fillAllRequiredFields()
    vm.origin = "Wild"
    vm.tagId = ""
    XCTAssertTrue(vm.isValid, "Wild origin should not require a tag ID")
  }

  // MARK: - reset() Tests

  func testReset_clearsTransientFields() {
    fillAllRequiredFields()
    vm.tagId = "HT-001"
    vm.notes = "Big fish"
    vm.classifiedWatersLicenseNumber = "CWL-123"

    vm.reset()

    XCTAssertEqual(vm.species, "", "species should be cleared")
    XCTAssertEqual(vm.sex, "", "sex should be cleared")
    XCTAssertEqual(vm.origin, "", "origin should be cleared")
    XCTAssertEqual(vm.lengthInches, 0, "lengthInches should be 0")
    XCTAssertEqual(vm.quality, "", "quality should be cleared")
    XCTAssertEqual(vm.tagId, "", "tagId should be cleared")
    XCTAssertEqual(vm.notes, "", "notes should be cleared")
    XCTAssertNil(vm.photo, "photo should be nil")
    XCTAssertNil(vm.photoPath, "photoPath should be nil")
    XCTAssertNil(vm.classifiedWatersLicenseNumber, "license number should be nil")
  }

  func testReset_preservesDefaults() {
    fillAllRequiredFields()
    vm.river = "Copper Creek"
    vm.guideName = "Mike Johnson"
    vm.tactic = "Nymphing"

    vm.reset()

    XCTAssertEqual(vm.river, "Copper Creek", "river should be preserved")
    XCTAssertEqual(vm.guideName, "Mike Johnson", "guideName should be preserved")
    XCTAssertEqual(vm.tactic, "Nymphing", "tactic should be preserved")
  }

  // MARK: - Lengths picker

  func testLengths_rangeIs20To45() {
    XCTAssertEqual(vm.lengths, Array(20...45), "Lengths picker should be 20-45 inches")
  }

  func testLengths_has26Elements() {
    XCTAssertEqual(vm.lengths.count, 26, "Should have 26 length options (20 through 45)")
  }

  // MARK: - Initial state

  func testInitialState_isNotSaving() {
    XCTAssertFalse(vm.isSaving)
  }

  func testInitialState_toastNotShown() {
    XCTAssertFalse(vm.showToast)
  }

  func testInitialState_defaultRiver() {
    XCTAssertEqual(vm.river, "Nehalem")
  }

  func testInitialState_defaultTactic() {
    XCTAssertEqual(vm.tactic, "Swinging")
  }

  func testInitialState_isNotValid() {
    XCTAssertFalse(vm.isValid, "Should be invalid with default empty fields")
  }
}
