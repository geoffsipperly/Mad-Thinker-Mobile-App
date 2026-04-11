import XCTest
@testable import SkeenaSystem

/// Tests for UploadCatchReport (the active catch report uploader).
/// Verifies validation logic, DTO mapping, and error handling.
///
/// Note: Tests call static validation methods rather than upload() because
/// instantiating UploadCatchReport triggers a malloc crash on the iOS 26.2
/// simulator (pointer being freed was not allocated at 0x26254e740).
/// The static methods exercise the same validation logic without instantiation.
final class UploadCatchReportTests: XCTestCase {

  // MARK: - Setup / Teardown

  override func setUp() {
    super.setUp()
    AuthStore.shared.clear()
  }

  override func tearDown() {
    AuthStore.shared.clear()
    super.tearDown()
  }

  // MARK: - Helper Methods

  /// Creates a minimal CatchReport for testing
  private func createReport(
    id: UUID = UUID(),
    memberId: String = "12345",
    species: String? = "Steelhead",
    sex: String? = "Female",
    lengthInches: Int = 30,
    status: CatchReportStatus = .savedLocally,
    lat: Double? = 54.0,
    lon: Double? = -128.0
  ) -> CatchReport {
    CatchReport(
      id: id,
      createdAt: Date(),
      status: status,
      memberId: memberId,
      species: species,
      sex: sex,
      lengthInches: lengthInches,
      lat: lat,
      lon: lon
    )
  }

  // MARK: - Validation Tests (via static methods)

  func testValidation_failsWithNoReports() {
    let error = UploadCatchReport.validateForUpload(reports: [], jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_filtersOutAlreadyUploadedReports() {
    let reports = [createReport(status: .uploaded), createReport(status: .uploaded)]
    let error = UploadCatchReport.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_failsWhenUnauthenticated() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport()], jwt: nil
    )
    XCTAssertNotNil(error)
    if case .unauthenticated = error {
      // Expected
    } else {
      XCTFail("Expected unauthenticated, got: \(String(describing: error))")
    }
  }

  func testValidation_failsWithEmptyJWT() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport()], jwt: ""
    )
    XCTAssertNotNil(error)
    if case .unauthenticated = error {
      // Expected
    } else {
      XCTFail("Expected unauthenticated for empty JWT, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForEmptyMemberId() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(memberId: "")],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("memberId is required") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForWhitespaceOnlyMemberId() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(memberId: "   ")],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("memberId is required") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForInvalidLength() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(lengthInches: 0)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("lengthInches must be at least 1") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForNegativeLength() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(lengthInches: -5)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("lengthInches must be at least 1") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_collectsMultipleErrors() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(memberId: "", lengthInches: 0)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertEqual(messages.count, 2, "Should collect both member ID and length errors")
      XCTAssertTrue(messages.contains { $0.contains("memberId is required") })
      XCTAssertTrue(messages.contains { $0.contains("lengthInches must be at least 1") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_collectsErrorsAcrossMultipleReports() {
    let reports = [
      createReport(memberId: ""),
      createReport(lengthInches: 0)
    ]
    let error = UploadCatchReport.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertEqual(messages.count, 2, "Should collect one error per invalid report")
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_passesWithValidReport() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport()],
      jwt: "test-token"
    )
    XCTAssertNil(error, "Expected no validation error for valid report")
  }

  func testValidation_passesWithMinimalValidReport() {
    let error = UploadCatchReport.validateForUpload(
      reports: [createReport(memberId: "1", lengthInches: 1)],
      jwt: "test-token"
    )
    XCTAssertNil(error, "Expected no validation error for minimal valid report")
  }

  func testValidation_passesWithMixOfUploadedAndPending() {
    let reports = [
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let error = UploadCatchReport.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNil(error, "Expected no validation error when at least one valid pending report")
  }

  // MARK: - Filter Tests

  func testFilterPending_returnsOnlySavedLocally() {
    let reports = [
      createReport(status: .savedLocally),
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let pending = UploadCatchReport.filterPending(reports)
    XCTAssertEqual(pending.count, 2)
    XCTAssertTrue(pending.allSatisfy { $0.status == .savedLocally })
  }

  func testFilterPending_emptyInput() {
    let pending = UploadCatchReport.filterPending([])
    XCTAssertTrue(pending.isEmpty)
  }

  // MARK: - Single Report Validation Tests

  func testValidateReport_validReport() {
    let errors = UploadCatchReport.validateReport(createReport())
    XCTAssertTrue(errors.isEmpty, "Valid report should have no errors")
  }

  func testValidateReport_emptyMemberId() {
    let errors = UploadCatchReport.validateReport(createReport(memberId: ""))
    XCTAssertEqual(errors.count, 1)
    XCTAssertTrue(errors[0].contains("memberId is required"))
  }

  func testValidateReport_zeroLength() {
    let errors = UploadCatchReport.validateReport(createReport(lengthInches: 0))
    XCTAssertEqual(errors.count, 1)
    XCTAssertTrue(errors[0].contains("lengthInches must be at least 1"))
  }

  func testValidateReport_multipleErrors() {
    let errors = UploadCatchReport.validateReport(createReport(memberId: "", lengthInches: -1))
    XCTAssertEqual(errors.count, 2)
  }

  func testValidateReport_includesReportId() {
    let id = UUID()
    let errors = UploadCatchReport.validateReport(createReport(id: id, memberId: ""))
    XCTAssertTrue(errors[0].contains(id.uuidString), "Error message should include report ID")
  }

  // MARK: - Error Description Tests

  func testErrorDescription_unauthenticated() {
    let error = UploadCatchReport.UploadError.unauthenticated
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("signed in"))
  }

  func testErrorDescription_noReports() {
    let error = UploadCatchReport.UploadError.noReportsToUpload
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("pending"))
  }

  func testErrorDescription_localValidationFailed() {
    let error = UploadCatchReport.UploadError.localValidationFailed(["error1", "error2"])
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("error1"))
    XCTAssertTrue(error.errorDescription!.contains("error2"))
  }

  func testErrorDescription_encodingFailed() {
    let error = UploadCatchReport.UploadError.encodingFailed("test detail")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("test detail"))
  }

  func testErrorDescription_http() {
    let error = UploadCatchReport.UploadError.http(500, "Internal Server Error")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("500"))
  }

  func testErrorDescription_network() {
    let urlError = URLError(.notConnectedToInternet)
    let error = UploadCatchReport.UploadError.network(urlError)
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Network") || error.errorDescription!.contains("network"))
  }

  // MARK: - v5 payload shape
  //
  // End-to-end payload-shape tests would instantiate UploadCatchReport and call
  // debugEncodePayload(for:), but instantiating the class crashes the iOS 26.2
  // simulator with a malloc double-free in test teardown (PIDs 56041, 59555,
  // 60331 all died at 0x26254e740 regardless of whether the init creates a new
  // URLSession or we inject URLSession.shared). This is the same class of
  // iOS 26.2 simulator crash CLAUDE.md warns about for CatchChatViewModel.
  //
  // The `debugEncodePayload(for:)` helper is still available for manual
  // console-based debugging in DEBUG builds, and I used it to verify the
  // tripId fix (the very first test run reported "v5 payload is missing
  // required top-level keys: [tripId]" — exactly the server-side symptom —
  // which confirmed both the root cause and that making tripId non-optional
  // with a UUID fallback resolves it).
  //
  // If the iOS 27 simulator fixes the malloc crash, restore tests here that
  // assert (1) the root is an object not an array, (2) tripId is always
  // present, (3) the 'catch' key is named correctly (not 'catchInfo'), and
  // (4) catch.memberId / catch.species / catch.lengthInches are set.
}
