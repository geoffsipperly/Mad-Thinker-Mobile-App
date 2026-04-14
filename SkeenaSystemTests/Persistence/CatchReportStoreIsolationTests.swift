import XCTest
@testable import SkeenaSystem

/// Verifies that `CatchReportStore` is strictly scoped by
/// `(memberId, communityId)` so that signing out, signing in as a different
/// user, or switching communities does NOT leak catch history across
/// identities. Also exercises the one-time migration from the legacy flat
/// layout to the scoped layout.
///
/// See the plan at `/Users/geoffsipperly/.claude/plans/kind-spinning-duckling.md`.
///
/// These tests build a non-singleton `CatchReportStore` anchored in a temp
/// directory with `autoRebind: false`, so they don't touch the real Documents
/// folder and don't depend on `AuthService`/`CommunityService` state.
@MainActor
final class CatchReportStoreIsolationTests: XCTestCase {

  // MARK: - Fixtures

  private var tempRoot: URL!

  override func setUp() {
    super.setUp()
    tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("CatchReportStoreIsolationTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let tempRoot {
      try? FileManager.default.removeItem(at: tempRoot)
    }
    tempRoot = nil
    super.tearDown()
  }

  // MARK: - Helpers

  /// Build a store anchored at the temp root with the auto-rebind Combine
  /// subscription disabled. Tests call `rebind(memberId:communityId:)` directly.
  private func makeStore() -> CatchReportStore {
    // Ensure the migration flag is clear so `migrateLegacyLayoutIfNeeded()`
    // actually runs when the store is instantiated.
    CatchReportStore.resetMigrationFlagForTesting()
    return CatchReportStore(rootDirectory: tempRoot, autoRebind: false)
  }

  /// Wait for the store's async `DispatchQueue.main.async { self.reports = ... }`
  /// updates to propagate before assertions.
  private func waitForStoreUpdate(_ description: String = "store update") {
    let expectation = expectation(description: description)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2.0)
  }

  private func makeReport(
    id: UUID = UUID(),
    memberId: String,
    communityId: String?,
    species: String = "rainbow_trout"
  ) -> CatchReport {
    CatchReport(
      id: id,
      memberId: memberId,
      species: species,
      lengthInches: 20,
      communityId: communityId,
      appVersion: "test",
      deviceDescription: "test",
      platform: "iOS"
    )
  }

  /// Encode a report and drop it into the legacy flat layout for migration tests.
  private func seedLegacyReport(_ report: CatchReport) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    let url = tempRoot.appendingPathComponent("report_\(report.id.uuidString).json")
    try data.write(to: url, options: [.atomic])
  }

  // MARK: - Cross-user / cross-community isolation

  func testRebind_crossUserIsolation() {
    let store = makeStore()

    // Bind to (A, X), create one report
    store.rebind(memberId: "memberA", communityId: "communityX")
    let reportA = makeReport(memberId: "memberA", communityId: "communityX")
    store.add(reportA)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1, "Scope (A, X) should see its own report")
    XCTAssertEqual(store.reports.first?.id, reportA.id)

    // Rebind to (B, Y) — should see nothing
    store.rebind(memberId: "memberB", communityId: "communityY")
    waitForStoreUpdate()
    XCTAssertTrue(store.reports.isEmpty, "Scope (B, Y) must not see (A, X)'s reports")

    // Rebind back to (A, X) — original report reappears
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, reportA.id, "Rebinding to the original scope should surface the original report")
  }

  func testRebind_crossCommunityIsolation_sameMember() {
    let store = makeStore()

    store.rebind(memberId: "memberA", communityId: "communityX")
    let reportX = makeReport(memberId: "memberA", communityId: "communityX")
    store.add(reportX)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)

    store.rebind(memberId: "memberA", communityId: "communityY")
    waitForStoreUpdate()
    XCTAssertTrue(store.reports.isEmpty, "Same member in a different community should see a disjoint list")

    let reportY = makeReport(memberId: "memberA", communityId: "communityY")
    store.add(reportY)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, reportY.id)

    // Back to X — only reportX
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.map(\.id), [reportX.id])
  }

  // MARK: - Unbound state

  func testUnboundState_writesAreDroppedAndReportsEmpty() {
    let store = makeStore()

    store.rebind(memberId: nil, communityId: nil)
    waitForStoreUpdate()
    XCTAssertTrue(store.reports.isEmpty)

    let report = makeReport(memberId: "memberA", communityId: "communityX")
    store.add(report)
    waitForStoreUpdate()
    XCTAssertTrue(store.reports.isEmpty, "add() while unbound should be a no-op")

    // No file should have been written under tempRoot
    let contents = (try? FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)) ?? []
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    XCTAssertTrue(jsonFiles.isEmpty, "Unbound add() must not touch disk")
  }

  func testUnboundState_partialIdentityTreatedAsUnbound() {
    let store = makeStore()

    // memberId only
    store.rebind(memberId: "memberA", communityId: nil)
    waitForStoreUpdate()
    XCTAssertNil(store.currentBoundDirectoryURL)

    // communityId only
    store.rebind(memberId: nil, communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertNil(store.currentBoundDirectoryURL)

    // Empty strings treated as nil
    store.rebind(memberId: "", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertNil(store.currentBoundDirectoryURL)
  }

  // MARK: - Migration

  func testMigration_validLegacyReport_movedIntoScopedFolder() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: "communityX")
    try seedLegacyReport(legacy)

    // Sanity: file is at the flat path
    let flatURL = tempRoot.appendingPathComponent("report_\(legacyId.uuidString).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: flatURL.path))

    // Instantiate the store — migration runs inside init
    let store = makeStore()

    // Flat file should be gone
    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path), "Legacy flat file should be moved after migration")

    // Scoped file should exist
    let scopedURL = tempRoot
      .appendingPathComponent("memberA", isDirectory: true)
      .appendingPathComponent("communityX", isDirectory: true)
      .appendingPathComponent("report_\(legacyId.uuidString).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: scopedURL.path), "Legacy report should be moved to the scoped directory")

    // Rebinding to (A, X) should load it
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, legacyId)
  }

  func testMigration_missingCommunityId_reportDeleted() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: nil)
    try seedLegacyReport(legacy)

    let flatURL = tempRoot.appendingPathComponent("report_\(legacyId.uuidString).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: flatURL.path))

    _ = makeStore()

    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path), "Legacy report with nil communityId should be deleted")

    // No scoped file should have been created for the missing community
    let memberDir = tempRoot.appendingPathComponent("memberA", isDirectory: true)
    let memberContents = (try? FileManager.default.contentsOfDirectory(at: memberDir, includingPropertiesForKeys: nil)) ?? []
    XCTAssertTrue(memberContents.isEmpty, "No scoped subfolder should be created for a dropped report")
  }

  func testMigration_emptyCommunityIdString_reportDeleted() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: "  ")
    try seedLegacyReport(legacy)

    _ = makeStore()

    let flatURL = tempRoot.appendingPathComponent("report_\(legacyId.uuidString).json")
    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path), "Whitespace-only communityId should be treated as missing and dropped")
  }

  func testMigration_corruptLegacyFile_quarantined() throws {
    let corruptURL = tempRoot.appendingPathComponent("report_\(UUID().uuidString).json")
    try Data("{ not valid json".utf8).write(to: corruptURL, options: [.atomic])

    _ = makeStore()

    XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path), "Corrupt legacy file should be moved out of the root")

    let quarantineDir = tempRoot.appendingPathComponent("_corrupt", isDirectory: true)
    let quarantined = (try? FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)) ?? []
    XCTAssertEqual(quarantined.count, 1, "Corrupt file should be quarantined under _corrupt/")
    XCTAssertTrue(quarantined.first?.lastPathComponent.hasSuffix(".bad") ?? false, "Quarantined file should carry a .bad suffix")
  }

  func testMigration_idempotent_flagPreventsRescan() throws {
    // Run migration once
    _ = makeStore()

    // Drop another legacy file AFTER the flag is set — it should NOT be migrated
    // on the next store creation because the flag short-circuits the scan.
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: "communityX")
    try seedLegacyReport(legacy)
    let flatURL = tempRoot.appendingPathComponent("report_\(legacyId.uuidString).json")

    // Create a new store *without* resetting the flag — simulate the real
    // production codepath after the first migration has completed.
    let store = CatchReportStore(rootDirectory: tempRoot, autoRebind: false)
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()

    XCTAssertTrue(FileManager.default.fileExists(atPath: flatURL.path), "Second migration pass should be skipped by the UserDefaults flag")
    XCTAssertTrue(store.reports.isEmpty, "Newly-dropped legacy file should not appear in the scoped list")
  }

  // MARK: - Upload semantics

  func testMarkUploaded_noOpWhenUnbound() {
    let store = makeStore()

    store.rebind(memberId: "memberA", communityId: "communityX")
    let report = makeReport(memberId: "memberA", communityId: "communityX")
    store.add(report)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.first?.status, .savedLocally)

    // Rebind away mid-flight
    store.rebind(memberId: nil, communityId: nil)
    waitForStoreUpdate()

    // markUploaded on an unbound store must not touch disk or throw
    store.markUploaded([report.id])
    waitForStoreUpdate()

    // Rebind back and verify the report still shows as .savedLocally
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.status, .savedLocally, "markUploaded() while unbound must be a no-op")
  }
}
