import XCTest
@testable import SkeenaSystem

/// Tests for UploadFarmedReports service.
///
/// Validates:
/// 1. Upload rejects empty report lists
/// 2. Upload rejects already-uploaded reports
/// 3. Upload fails when unauthenticated
/// 4. Reports without GPS coordinates are skipped
/// 5. Error descriptions are user-friendly
///
/// Note: Tests call static validation methods rather than upload() because
/// instantiating UploadFarmedReports triggers a malloc crash on the iOS 26.2
/// simulator (pointer being freed was not allocated at 0x26254e740).
/// The static methods exercise the same validation logic without instantiation.
final class UploadFarmedReportsTests: XCTestCase {

  // MARK: - Setup / Teardown

  override func setUp() {
    super.setUp()
    AuthStore.shared.clear()
  }

  override func tearDown() {
    AuthStore.shared.clear()
    super.tearDown()
  }

  // MARK: - Helpers

  private func createReport(
    id: UUID = UUID(),
    status: FarmedReportStatus = .savedLocally,
    guideName: String = "Test Guide",
    lat: Double? = 54.5,
    lon: Double? = -128.6,
    anglerNumber: String? = nil
  ) -> FarmedReport {
    FarmedReport(
      id: id,
      createdAt: Date(),
      status: status,
      guideName: guideName,
      lat: lat,
      lon: lon,
      anglerNumber: anglerNumber
    )
  }

  // MARK: - Validation Tests (via static methods)

  func testValidation_failsWithEmptyReportList() {
    let error = UploadFarmedReports.validateForUpload(reports: [], jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_filtersOutAlreadyUploadedReports() {
    let reports = [createReport(status: .uploaded), createReport(status: .uploaded)]
    let error = UploadFarmedReports.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .noReportsToUpload = error {
      // Expected
    } else {
      XCTFail("Expected noReportsToUpload, got: \(String(describing: error))")
    }
  }

  func testValidation_failsWhenUnauthenticated() {
    let error = UploadFarmedReports.validateForUpload(reports: [createReport()], jwt: nil)
    XCTAssertNotNil(error)
    if case .unauthenticated = error {
      // Expected
    } else {
      XCTFail("Expected unauthenticated, got: \(String(describing: error))")
    }
  }

  func testValidation_failsWithEmptyJWT() {
    let error = UploadFarmedReports.validateForUpload(reports: [createReport()], jwt: "")
    XCTAssertNotNil(error)
    if case .unauthenticated = error {
      // Expected
    } else {
      XCTFail("Expected unauthenticated for empty JWT, got: \(String(describing: error))")
    }
  }

  func testValidation_skipsReportsWithoutGPS() {
    let reports = [createReport(lat: nil, lon: nil), createReport(lat: nil, lon: nil)]
    let error = UploadFarmedReports.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNotNil(error)
    if case .encodingFailed(let msg) = error {
      XCTAssertTrue(msg.contains("GPS"), "Error should mention GPS: \(msg)")
    } else {
      XCTFail("Expected encodingFailed, got: \(String(describing: error))")
    }
  }

  func testValidation_skipsReportsWithPartialGPS_latOnly() {
    let error = UploadFarmedReports.validateForUpload(
      reports: [createReport(lat: 54.5, lon: nil)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .encodingFailed = error {
      // Expected
    } else {
      XCTFail("Expected encodingFailed for partial GPS, got: \(String(describing: error))")
    }
  }

  func testValidation_skipsReportsWithPartialGPS_lonOnly() {
    let error = UploadFarmedReports.validateForUpload(
      reports: [createReport(lat: nil, lon: -128.6)],
      jwt: "test-token"
    )
    XCTAssertNotNil(error)
    if case .encodingFailed = error {
      // Expected
    } else {
      XCTFail("Expected encodingFailed for partial GPS, got: \(String(describing: error))")
    }
  }

  func testValidation_passesWithValidReport() {
    let error = UploadFarmedReports.validateForUpload(
      reports: [createReport()],
      jwt: "test-token"
    )
    XCTAssertNil(error, "Expected no validation error for valid report")
  }

  func testValidation_passesWithMixOfUploadedAndPending() {
    let reports = [
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let error = UploadFarmedReports.validateForUpload(reports: reports, jwt: "test-token")
    XCTAssertNil(error, "Expected no validation error when at least one pending report has GPS")
  }

  // MARK: - Filter Tests

  func testFilterPending_returnsOnlySavedLocally() {
    let reports = [
      createReport(status: .savedLocally),
      createReport(status: .uploaded),
      createReport(status: .savedLocally)
    ]
    let pending = UploadFarmedReports.filterPending(reports)
    XCTAssertEqual(pending.count, 2)
    XCTAssertTrue(pending.allSatisfy { $0.status == .savedLocally })
  }

  func testFilterPending_emptyInput() {
    let pending = UploadFarmedReports.filterPending([])
    XCTAssertTrue(pending.isEmpty)
  }

  func testFilterWithGPS_returnsOnlyCompleteCoordinates() {
    let reports = [
      createReport(lat: 54.5, lon: -128.6),
      createReport(lat: nil, lon: -128.6),
      createReport(lat: 54.5, lon: nil),
      createReport(lat: nil, lon: nil)
    ]
    let withGPS = UploadFarmedReports.filterWithGPS(reports)
    XCTAssertEqual(withGPS.count, 1)
  }

  // MARK: - River Resolution Tests

  func testResolveRiverName_nearNehalemRiver_returnsNehalem() {
    // Placeholder coordinate for Nehalem River in RiverCoordinates.swift
    let river = UploadFarmedReports.resolveRiverName(lat: 45.7060, lon: -123.8810)
    XCTAssertEqual(river, "Nehalem")
  }

  func testResolveRiverName_nearWilsonRiver_returnsWilson() {
    // Placeholder coordinate for Wilson River in RiverCoordinates.swift
    let river = UploadFarmedReports.resolveRiverName(lat: 45.4730, lon: -123.7350)
    XCTAssertEqual(river, "Wilson")
  }

  func testResolveRiverName_nearTraskRiver_returnsTrask() {
    // Placeholder coordinate for Trask River in RiverCoordinates.swift
    let river = UploadFarmedReports.resolveRiverName(lat: 45.4100, lon: -123.7200)
    XCTAssertEqual(river, "Trask")
  }

  func testResolveRiverName_nearNestuccaRiver_returnsNestucca() {
    // Placeholder coordinate for Nestucca River in RiverCoordinates.swift
    let river = UploadFarmedReports.resolveRiverName(lat: 43.7830, lon: -121.6370)
    XCTAssertEqual(river, "Nestucca")
  }

  func testResolveRiverName_farFromAllRivers_returnsDefaultRiver() {
    // Portland, OR — far from any Oregon Coast river
    let river = UploadFarmedReports.resolveRiverName(lat: 45.5152, lon: -122.6784)
    let expected = AppEnvironment.shared.defaultRiver
    XCTAssertEqual(river, expected,
                   "Location far from all rivers should fall back to defaultRiver")
  }

  // MARK: - Error Description Tests

  func testErrorDescription_unauthenticated() {
    let error = UploadFarmedReports.UploadError.unauthenticated
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("signed in"))
  }

  func testErrorDescription_noReports() {
    let error = UploadFarmedReports.UploadError.noReportsToUpload
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("pending"))
  }

  func testErrorDescription_encodingFailed() {
    let error = UploadFarmedReports.UploadError.encodingFailed("test detail")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("test detail"))
  }

  func testErrorDescription_http() {
    let error = UploadFarmedReports.UploadError.http(500, "Internal Server Error")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("500"))
  }

  func testErrorDescription_network() {
    let urlError = URLError(.notConnectedToInternet)
    let error = UploadFarmedReports.UploadError.network(urlError)
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Network"))
  }

  // MARK: - Status Enum Tests

  func testFarmedReportStatus_allCases() {
    XCTAssertEqual(FarmedReportStatus.allCases.count, 2)
    XCTAssertTrue(FarmedReportStatus.allCases.contains(.savedLocally))
    XCTAssertTrue(FarmedReportStatus.allCases.contains(.uploaded))
  }
}
