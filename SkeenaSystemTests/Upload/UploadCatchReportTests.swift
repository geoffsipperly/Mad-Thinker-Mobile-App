import XCTest
@testable import SkeenaSystem

/// Tests for UploadCatchPicMemo (the active catch report uploader).
/// Verifies validation logic, DTO mapping, and error handling.
///
/// Note: Tests call static validation methods rather than upload() because
/// instantiating UploadCatchPicMemo triggers a malloc crash on the iOS 26.2
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

  /// Creates a minimal CatchReportPicMemo for testing
  private func createReport(
    id: UUID = UUID(),
    anglerNumber: String = "12345",
    species: String? = "Steelhead",
    sex: String? = "Female",
    origin: String? = "Wild",
    lengthInches: Int = 30,
    status: CatchReportPicMemoStatus = .savedLocally,
    lat: Double? = 54.0,
    lon: Double? = -128.0
  ) -> CatchReportPicMemo {
    CatchReportPicMemo(
      id: id,
      createdAt: Date(),
      status: status,
      anglerNumber: anglerNumber,
      species: species,
      sex: sex,
      origin: origin,
      lengthInches: lengthInches,
      lat: lat,
      lon: lon
    )
  }

  // MARK: - Validation Tests (via static methods)

  func testValidation_failsWithNoReports() {
    let error = UploadCatchPicMemo.validateForUpload(reports: [], jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_filtersOutAlreadyUploadedReports() {
    let reports = [createReport(status: .uploaded), createReport(status: .uploaded)]
    let error = UploadCatchPicMemo.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_failsWhenUnauthenticated() {
    let error = UploadCatchPicMemo.validateForUpload(
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
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport()], jwt: ""
    )
    XCTAssertNotNil(error)
    if case .unauthenticated = error {
      // Expected
    } else {
      XCTFail("Expected unauthenticated for empty JWT, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForEmptyAnglerNumber() {
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport(anglerNumber: "")],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("anglerNumber is required") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForWhitespaceOnlyAnglerNumber() {
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport(anglerNumber: "   ")],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertTrue(messages.contains { $0.contains("anglerNumber is required") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_failsForInvalidLength() {
    let error = UploadCatchPicMemo.validateForUpload(
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
    let error = UploadCatchPicMemo.validateForUpload(
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
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport(anglerNumber: "", lengthInches: 0)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertEqual(messages.count, 2, "Should collect both angler number and length errors")
      XCTAssertTrue(messages.contains { $0.contains("anglerNumber is required") })
      XCTAssertTrue(messages.contains { $0.contains("lengthInches must be at least 1") })
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_collectsErrorsAcrossMultipleReports() {
    let reports = [
      createReport(anglerNumber: ""),
      createReport(lengthInches: 0)
    ]
    let error = UploadCatchPicMemo.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .localValidationFailed(let messages) = error {
      XCTAssertEqual(messages.count, 2, "Should collect one error per invalid report")
    } else {
      XCTFail("Expected localValidationFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_passesWithValidReport() {
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport()],
      jwt: "test-token"
    )
    XCTAssertNil(error, "Expected no validation error for valid report")
  }

  func testValidation_passesWithMinimalValidReport() {
    let error = UploadCatchPicMemo.validateForUpload(
      reports: [createReport(anglerNumber: "1", lengthInches: 1)],
      jwt: "test-token"
    )
    XCTAssertNil(error, "Expected no validation error for minimal valid report")
  }

  func testValidation_passesWithMixOfUploadedAndPending() {
    let reports = [
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let error = UploadCatchPicMemo.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNil(error, "Expected no validation error when at least one valid pending report")
  }

  // MARK: - Filter Tests

  func testFilterPending_returnsOnlySavedLocally() {
    let reports = [
      createReport(status: .savedLocally),
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let pending = UploadCatchPicMemo.filterPending(reports)
    XCTAssertEqual(pending.count, 2)
    XCTAssertTrue(pending.allSatisfy { $0.status == .savedLocally })
  }

  func testFilterPending_emptyInput() {
    let pending = UploadCatchPicMemo.filterPending([])
    XCTAssertTrue(pending.isEmpty)
  }

  // MARK: - Single Report Validation Tests

  func testValidateReport_validReport() {
    let errors = UploadCatchPicMemo.validateReport(createReport())
    XCTAssertTrue(errors.isEmpty, "Valid report should have no errors")
  }

  func testValidateReport_emptyAnglerNumber() {
    let errors = UploadCatchPicMemo.validateReport(createReport(anglerNumber: ""))
    XCTAssertEqual(errors.count, 1)
    XCTAssertTrue(errors[0].contains("anglerNumber is required"))
  }

  func testValidateReport_zeroLength() {
    let errors = UploadCatchPicMemo.validateReport(createReport(lengthInches: 0))
    XCTAssertEqual(errors.count, 1)
    XCTAssertTrue(errors[0].contains("lengthInches must be at least 1"))
  }

  func testValidateReport_multipleErrors() {
    let errors = UploadCatchPicMemo.validateReport(createReport(anglerNumber: "", lengthInches: -1))
    XCTAssertEqual(errors.count, 2)
  }

  func testValidateReport_includesReportId() {
    let id = UUID()
    let errors = UploadCatchPicMemo.validateReport(createReport(id: id, anglerNumber: ""))
    XCTAssertTrue(errors[0].contains(id.uuidString), "Error message should include report ID")
  }

  // MARK: - Error Description Tests

  func testErrorDescription_unauthenticated() {
    let error = UploadCatchPicMemo.UploadError.unauthenticated
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("signed in"))
  }

  func testErrorDescription_noReports() {
    let error = UploadCatchPicMemo.UploadError.noReportsToUpload
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("pending"))
  }

  func testErrorDescription_localValidationFailed() {
    let error = UploadCatchPicMemo.UploadError.localValidationFailed(["error1", "error2"])
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("error1"))
    XCTAssertTrue(error.errorDescription!.contains("error2"))
  }

  func testErrorDescription_encodingFailed() {
    let error = UploadCatchPicMemo.UploadError.encodingFailed("test detail")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("test detail"))
  }

  func testErrorDescription_http() {
    let error = UploadCatchPicMemo.UploadError.http(500, "Internal Server Error")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("500"))
  }

  func testErrorDescription_network() {
    let urlError = URLError(.notConnectedToInternet)
    let error = UploadCatchPicMemo.UploadError.network(urlError)
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Network") || error.errorDescription!.contains("network"))
  }
}
