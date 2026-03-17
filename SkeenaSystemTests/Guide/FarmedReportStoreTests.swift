import XCTest
@testable import SkeenaSystem

/// Tests for FarmedReportStore file-based JSON persistence.
///
/// Validates:
/// 1. add() persists a report to disk and loads it back
/// 2. add() forces status to .savedLocally
/// 3. update() overwrites an existing report
/// 4. delete() removes a report from disk and from the in-memory list
/// 5. markUploaded() changes status to .uploaded
/// 6. refresh() reloads from disk
/// 7. Reports are sorted newest-first
/// 8. Multiple add/delete operations work correctly
@MainActor
final class FarmedReportStoreTests: XCTestCase {

  // MARK: - Properties

  private let store = FarmedReportStore.shared
  private var createdIDs: [UUID] = []

  // MARK: - Lifecycle

  override func tearDown() {
    // Clean up any reports created during each test
    for id in createdIDs {
      if let report = store.reports.first(where: { $0.id == id }) {
        store.delete(report)
      }
    }
    createdIDs.removeAll()

    // Allow async loadAll to settle
    let expectation = expectation(description: "Store settled after cleanup")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2.0)

    super.tearDown()
  }

  // MARK: - Helpers

  private func makeReport(
    guideName: String = "Test Guide",
    lat: Double? = 54.5,
    lon: Double? = -128.6,
    anglerNumber: String? = nil,
    status: FarmedReportStatus = .savedLocally
  ) -> FarmedReport {
    let report = FarmedReport(
      id: UUID(),
      createdAt: Date(),
      status: status,
      guideName: guideName,
      lat: lat,
      lon: lon,
      anglerNumber: anglerNumber
    )
    createdIDs.append(report.id)
    return report
  }

  /// Wait for the store's async loadAll to propagate to @Published reports.
  private func waitForStoreUpdate() {
    let expectation = expectation(description: "Store update")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2.0)
  }

  // MARK: - add Tests

  func testAdd_reportAppearsInStore() {
    let report = makeReport(guideName: "Alice")
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertNotNil(found, "Added report should appear in store")
    XCTAssertEqual(found?.guideName, "Alice")
  }

  func testAdd_forcesStatusToSavedLocally() {
    let report = makeReport(status: .uploaded)
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.status, .savedLocally, "add() should force status to .savedLocally")
  }

  func testAdd_preservesGPSCoordinates() {
    let report = makeReport(lat: 55.123, lon: -127.456)
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertNotNil(found?.lat, "lat should be present")
    XCTAssertNotNil(found?.lon, "lon should be present")
    if let lat = found?.lat, let lon = found?.lon {
      XCTAssertEqual(lat, 55.123, accuracy: 0.001)
      XCTAssertEqual(lon, -127.456, accuracy: 0.001)
    }
  }

  func testAdd_preservesAnglerNumber() {
    let report = makeReport(anglerNumber: "ANG-001")
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.anglerNumber, "ANG-001")
  }

  func testAdd_nilAnglerNumber_preserved() {
    let report = makeReport(anglerNumber: nil)
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertNil(found?.anglerNumber)
  }

  func testAdd_nilCoordinates_preserved() {
    let report = makeReport(lat: nil, lon: nil)
    store.add(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertNil(found?.lat)
    XCTAssertNil(found?.lon)
  }

  // MARK: - update Tests

  func testUpdate_changesGuideName() {
    var report = makeReport(guideName: "Before")
    store.add(report)
    waitForStoreUpdate()

    report.guideName = "After"
    store.update(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.guideName, "After", "Guide name should be updated")
  }

  func testUpdate_changesAnglerNumber() {
    var report = makeReport(anglerNumber: nil)
    store.add(report)
    waitForStoreUpdate()

    report.anglerNumber = "ANG-UPDATED"
    store.update(report)
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.anglerNumber, "ANG-UPDATED")
  }

  // MARK: - delete Tests

  func testDelete_removesReportFromStore() {
    let report = makeReport()
    store.add(report)
    waitForStoreUpdate()

    XCTAssertNotNil(store.reports.first(where: { $0.id == report.id }), "Report should exist before delete")

    store.delete(report)
    // Remove from cleanup list since we already deleted
    createdIDs.removeAll(where: { $0 == report.id })
    waitForStoreUpdate()

    XCTAssertNil(store.reports.first(where: { $0.id == report.id }), "Report should be gone after delete")
  }

  // MARK: - markUploaded Tests

  func testMarkUploaded_changesStatusToUploaded() {
    let report = makeReport()
    store.add(report)
    waitForStoreUpdate()

    store.markUploaded([report.id])
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.status, .uploaded, "Status should change to .uploaded")
  }

  func testMarkUploaded_onlyAffectsSpecifiedIDs() {
    let report1 = makeReport(guideName: "One")
    let report2 = makeReport(guideName: "Two")
    store.add(report1)
    store.add(report2)
    waitForStoreUpdate()

    store.markUploaded([report1.id])
    waitForStoreUpdate()

    let found1 = store.reports.first(where: { $0.id == report1.id })
    let found2 = store.reports.first(where: { $0.id == report2.id })
    XCTAssertEqual(found1?.status, .uploaded, "Report 1 should be uploaded")
    XCTAssertEqual(found2?.status, .savedLocally, "Report 2 should remain savedLocally")
  }

  func testMarkUploaded_emptyArray_noChanges() {
    let report = makeReport()
    store.add(report)
    waitForStoreUpdate()

    store.markUploaded([])
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.status, .savedLocally, "Empty markUploaded should not change anything")
  }

  func testMarkUploaded_nonexistentID_noChanges() {
    let report = makeReport()
    store.add(report)
    waitForStoreUpdate()

    store.markUploaded([UUID()])
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertEqual(found?.status, .savedLocally, "Non-matching ID should not change report status")
  }

  // MARK: - refresh Tests

  func testRefresh_reloadsFromDisk() {
    let report = makeReport()
    store.add(report)
    waitForStoreUpdate()

    store.refresh()
    waitForStoreUpdate()

    let found = store.reports.first(where: { $0.id == report.id })
    XCTAssertNotNil(found, "Report should still be present after refresh")
  }

  // MARK: - Sorting Tests

  func testReports_sortedNewestFirst() {
    let oldDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
    let newDate = Date()

    let oldReport = FarmedReport(
      id: UUID(),
      createdAt: oldDate,
      status: .savedLocally,
      guideName: "Old"
    )
    createdIDs.append(oldReport.id)

    let newReport = FarmedReport(
      id: UUID(),
      createdAt: newDate,
      status: .savedLocally,
      guideName: "New"
    )
    createdIDs.append(newReport.id)

    // Add old first, then new
    store.add(oldReport)
    store.add(newReport)
    waitForStoreUpdate()

    let testIDs = Set([oldReport.id, newReport.id])
    let testReports = store.reports.filter { testIDs.contains($0.id) }

    XCTAssertGreaterThanOrEqual(testReports.count, 2, "Both reports should be in the store")

    if testReports.count >= 2 {
      XCTAssertEqual(testReports[0].guideName, "New", "Newest report should come first")
      XCTAssertEqual(testReports[1].guideName, "Old", "Oldest report should come second")
    }
  }

  // MARK: - Purge Old Uploaded Tests

  func testPurgeOldUploaded_removesOldUploadedReports() {
    // Create a report with a createdAt 20 days ago
    let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
    let oldReport = FarmedReport(
      id: UUID(),
      createdAt: oldDate,
      status: .savedLocally,
      guideName: "Old Uploaded"
    )
    createdIDs.append(oldReport.id)

    store.add(oldReport)
    waitForStoreUpdate()

    // Mark it as uploaded
    store.markUploaded([oldReport.id])
    waitForStoreUpdate()

    XCTAssertNotNil(store.reports.first(where: { $0.id == oldReport.id }),
                    "Report should exist before purge")

    // Purge reports older than 14 days
    store.purgeOldUploaded(olderThanDays: 14)
    createdIDs.removeAll(where: { $0 == oldReport.id })
    waitForStoreUpdate()

    XCTAssertNil(store.reports.first(where: { $0.id == oldReport.id }),
                 "Old uploaded report should be purged")
  }

  func testPurgeOldUploaded_keepsRecentUploadedReports() {
    // Create a report with a createdAt 5 days ago
    let recentDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
    let recentReport = FarmedReport(
      id: UUID(),
      createdAt: recentDate,
      status: .savedLocally,
      guideName: "Recent Uploaded"
    )
    createdIDs.append(recentReport.id)

    store.add(recentReport)
    waitForStoreUpdate()

    store.markUploaded([recentReport.id])
    waitForStoreUpdate()

    store.purgeOldUploaded(olderThanDays: 14)
    waitForStoreUpdate()

    XCTAssertNotNil(store.reports.first(where: { $0.id == recentReport.id }),
                    "Recent uploaded report should NOT be purged")
  }

  func testPurgeOldUploaded_keepsSavedLocallyReportsRegardlessOfAge() {
    // Create an old report that is still savedLocally
    let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    let oldPending = FarmedReport(
      id: UUID(),
      createdAt: oldDate,
      status: .savedLocally,
      guideName: "Old Pending"
    )
    createdIDs.append(oldPending.id)

    store.add(oldPending)
    waitForStoreUpdate()

    store.purgeOldUploaded(olderThanDays: 14)
    waitForStoreUpdate()

    XCTAssertNotNil(store.reports.first(where: { $0.id == oldPending.id }),
                    "Old savedLocally report should NOT be purged")
  }

  // MARK: - Multiple Operations Tests

  func testMultipleAdds_allPersisted() {
    let reports = (0..<3).map { i in
      makeReport(guideName: "Guide \(i)")
    }

    for report in reports {
      store.add(report)
    }
    waitForStoreUpdate()

    for report in reports {
      let found = store.reports.first(where: { $0.id == report.id })
      XCTAssertNotNil(found, "Report \(report.guideName) should be in the store")
    }
  }

  func testAddThenDeleteThenAdd_worksCorrectly() {
    let report1 = makeReport(guideName: "First")
    store.add(report1)
    waitForStoreUpdate()

    store.delete(report1)
    createdIDs.removeAll(where: { $0 == report1.id })
    waitForStoreUpdate()

    XCTAssertNil(store.reports.first(where: { $0.id == report1.id }), "Deleted report should be gone")

    let report2 = makeReport(guideName: "Second")
    store.add(report2)
    waitForStoreUpdate()

    XCTAssertNotNil(store.reports.first(where: { $0.id == report2.id }), "New report should be present")
  }
}
