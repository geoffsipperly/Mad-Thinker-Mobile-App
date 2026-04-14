// Bend Fly Shop
//
// UploadCoordinatorTests.swift — Tests for the unified upload sequencer.

import XCTest
@testable import SkeenaSystem

final class UploadCoordinatorTests: XCTestCase {

  // MARK: - Result struct

  func testUploadResult_defaultValues() {
    let result = UploadCoordinator.UploadResult()
    XCTAssertEqual(result.catchesUploaded, 0)
    XCTAssertEqual(result.marksUploaded, 0)
    XCTAssertEqual(result.notesUploaded, 0)
    XCTAssertEqual(result.totalUploaded, 0)
    XCTAssertTrue(result.errors.isEmpty)
    XCTAssertFalse(result.hasErrors)
  }

  func testUploadResult_totalUploaded_sumsAllThree() {
    var result = UploadCoordinator.UploadResult()
    result.catchesUploaded = 3
    result.marksUploaded = 2
    result.notesUploaded = 1
    XCTAssertEqual(result.totalUploaded, 6)
  }

  func testUploadResult_hasErrors_trueWhenErrorsPresent() {
    var result = UploadCoordinator.UploadResult()
    result.errors.append("Test error")
    XCTAssertTrue(result.hasErrors)
  }

  func testUploadResult_summary_nothingToUpload() {
    let result = UploadCoordinator.UploadResult()
    XCTAssertEqual(result.summary, "Nothing to upload")
  }

  func testUploadResult_summary_mixedUploads() {
    var result = UploadCoordinator.UploadResult()
    result.catchesUploaded = 2
    result.marksUploaded = 1
    result.notesUploaded = 3
    XCTAssertTrue(result.summary.contains("2 reports"))
    XCTAssertTrue(result.summary.contains("1 mark"))
    XCTAssertTrue(result.summary.contains("3 notes"))
  }

  func testUploadResult_summary_singularPlural() {
    var result = UploadCoordinator.UploadResult()
    result.catchesUploaded = 1
    XCTAssertTrue(result.summary.contains("1 report"))
    XCTAssertFalse(result.summary.contains("1 reports"))
  }

  func testUploadResult_summary_includesErrors() {
    var result = UploadCoordinator.UploadResult()
    result.catchesUploaded = 1
    result.errors.append("Network timeout")
    XCTAssertTrue(result.summary.contains("Errors:"))
    XCTAssertTrue(result.summary.contains("Network timeout"))
  }

  // MARK: - Coordinator instantiation

  func testUploadCoordinator_instantiatesWithoutCrash() {
    let coordinator = UploadCoordinator()
    XCTAssertNotNil(coordinator)
  }

  // MARK: - Empty upload completes immediately

  func testUploadAll_noPendingItems_completesWithEmptyResult() {
    let coordinator = UploadCoordinator()
    let expectation = expectation(description: "completion called")

    // Dummy catch uploader (won't be used since catches is empty)
    let config = UploadCatchReport.Config(
      endpoint: URL(string: "https://invalid.local")!,
      appVersion: "1.0.0",
      apiKey: "test"
    )
    let catchUploader = UploadCatchReport(config: config)

    coordinator.uploadAll(
      catches: [],
      marks: [],
      observations: [],
      memberId: "MAD000000",
      catchUploader: catchUploader,
      progress: { _ in },
      completion: { result in
        XCTAssertEqual(result.totalUploaded, 0)
        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(result.summary, "Nothing to upload")
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 2)
  }
}
