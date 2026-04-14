import XCTest
@testable import SkeenaSystem

/// Mirror of `CatchReportStoreIsolationTests` for `FarmedReportStore`.
/// Verifies cross-user / cross-community scoping and the one-time legacy
/// layout migration. See the plan at
/// `/Users/geoffsipperly/.claude/plans/kind-spinning-duckling.md`.
@MainActor
final class FarmedReportStoreIsolationTests: XCTestCase {

  // MARK: - Fixtures

  private var tempRoot: URL!

  override func setUp() {
    super.setUp()
    tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("FarmedReportStoreIsolationTests-\(UUID().uuidString)", isDirectory: true)
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

  private func makeStore() -> FarmedReportStore {
    FarmedReportStore.resetMigrationFlagForTesting()
    return FarmedReportStore(rootDirectory: tempRoot, autoRebind: false)
  }

  private func waitForStoreUpdate(_ description: String = "store update") {
    let expectation = expectation(description: description)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2.0)
  }

  private func makeReport(
    id: UUID = UUID(),
    memberId: String?,
    communityId: String?,
    eventType: NoCatchEventType = .farmed,
    guideName: String = "Test Guide"
  ) -> FarmedReport {
    FarmedReport(
      id: id,
      createdAt: Date(),
      status: .savedLocally,
      eventType: eventType,
      guideName: guideName,
      lat: 54.5,
      lon: -128.6,
      memberId: memberId,
      communityId: communityId
    )
  }

  private func seedLegacyReport(_ report: FarmedReport) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    let url = tempRoot.appendingPathComponent("farmed_\(report.id.uuidString).json")
    try data.write(to: url, options: [.atomic])
  }

  // MARK: - Isolation

  func testRebind_crossUserIsolation() {
    let store = makeStore()

    store.rebind(memberId: "memberA", communityId: "communityX")
    let reportA = makeReport(memberId: "memberA", communityId: "communityX")
    store.add(reportA)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, reportA.id)

    store.rebind(memberId: "memberB", communityId: "communityY")
    waitForStoreUpdate()
    XCTAssertTrue(store.reports.isEmpty, "Scope (B, Y) must not see (A, X)'s reports")

    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, reportA.id)
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
    XCTAssertTrue(store.reports.isEmpty)

    let reportY = makeReport(memberId: "memberA", communityId: "communityY")
    store.add(reportY)
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, reportY.id)

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
    XCTAssertTrue(store.reports.isEmpty)

    let contents = (try? FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)) ?? []
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    XCTAssertTrue(jsonFiles.isEmpty, "Unbound add() must not touch disk")
  }

  // MARK: - Migration

  func testMigration_validLegacyReport_movedIntoScopedFolder() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: "communityX")
    try seedLegacyReport(legacy)

    let flatURL = tempRoot.appendingPathComponent("farmed_\(legacyId.uuidString).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: flatURL.path))

    let store = makeStore()

    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path))

    let scopedURL = tempRoot
      .appendingPathComponent("memberA", isDirectory: true)
      .appendingPathComponent("communityX", isDirectory: true)
      .appendingPathComponent("farmed_\(legacyId.uuidString).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: scopedURL.path))

    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()
    XCTAssertEqual(store.reports.count, 1)
    XCTAssertEqual(store.reports.first?.id, legacyId)
  }

  func testMigration_missingMemberId_reportDeleted() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: nil, communityId: "communityX")
    try seedLegacyReport(legacy)

    _ = makeStore()

    let flatURL = tempRoot.appendingPathComponent("farmed_\(legacyId.uuidString).json")
    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path))
  }

  func testMigration_missingCommunityId_reportDeleted() throws {
    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: nil)
    try seedLegacyReport(legacy)

    _ = makeStore()

    let flatURL = tempRoot.appendingPathComponent("farmed_\(legacyId.uuidString).json")
    XCTAssertFalse(FileManager.default.fileExists(atPath: flatURL.path))

    let memberDir = tempRoot.appendingPathComponent("memberA", isDirectory: true)
    let memberContents = (try? FileManager.default.contentsOfDirectory(at: memberDir, includingPropertiesForKeys: nil)) ?? []
    XCTAssertTrue(memberContents.isEmpty)
  }

  func testMigration_corruptLegacyFile_quarantined() throws {
    let corruptURL = tempRoot.appendingPathComponent("farmed_\(UUID().uuidString).json")
    try Data("{ not valid json".utf8).write(to: corruptURL, options: [.atomic])

    _ = makeStore()

    XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))

    let quarantineDir = tempRoot.appendingPathComponent("_corrupt", isDirectory: true)
    let quarantined = (try? FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)) ?? []
    XCTAssertEqual(quarantined.count, 1)
    XCTAssertTrue(quarantined.first?.lastPathComponent.hasSuffix(".bad") ?? false)
  }

  func testMigration_idempotent_flagPreventsRescan() throws {
    _ = makeStore()

    let legacyId = UUID()
    let legacy = makeReport(id: legacyId, memberId: "memberA", communityId: "communityX")
    try seedLegacyReport(legacy)
    let flatURL = tempRoot.appendingPathComponent("farmed_\(legacyId.uuidString).json")

    let store = FarmedReportStore(rootDirectory: tempRoot, autoRebind: false)
    store.rebind(memberId: "memberA", communityId: "communityX")
    waitForStoreUpdate()

    XCTAssertTrue(FileManager.default.fileExists(atPath: flatURL.path))
    XCTAssertTrue(store.reports.isEmpty)
  }
}
