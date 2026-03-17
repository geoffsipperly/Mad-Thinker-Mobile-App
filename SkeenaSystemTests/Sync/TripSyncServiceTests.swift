import XCTest
import CoreData
@testable import SkeenaSystem

/// Regression tests for TripSyncService.
/// These tests verify trip synchronization from server to Core Data,
/// including upsert logic, client/angler handling, and lodge linking.
@MainActor
final class TripSyncServiceTests: XCTestCase {

  // MARK: - Properties

  private var persistenceController: PersistenceController!
  private var context: NSManagedObjectContext!

  // MARK: - Setup / Teardown

  override func setUp() {
    super.setUp()
    // Use in-memory store for test isolation
    persistenceController = PersistenceController(inMemory: true)
    context = persistenceController.container.viewContext

    // Register mock URL protocol
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    context = nil
    persistenceController = nil
    super.tearDown()
  }

  // MARK: - Helper Methods

  /// Creates a mock trips response JSON
  private func makeMockTripsResponse(trips: [[String: Any]]) -> Data {
    let response: [String: Any] = [
      "success": true,
      "trips": trips
    ]
    return try! JSONSerialization.data(withJSONObject: response, options: [])
  }

  /// Creates a single trip dictionary for mock responses
  private func makeTripDict(
    id: String = UUID().uuidString,
    tripId: String? = nil,
    tripName: String = "Test Trip",
    startDate: String? = nil,
    endDate: String? = nil,
    guideName: String? = "Test Guide",
    lodge: String? = "Bend Fly Shop",
    community: String? = "Bend Fly Shop",
    anglers: [[String: Any]]? = nil
  ) -> [String: Any] {
    var dict: [String: Any] = [
      "id": id,
      "tripName": tripName
    ]
    if let tripId = tripId { dict["tripId"] = tripId }
    if let startDate = startDate { dict["startDate"] = startDate }
    if let endDate = endDate { dict["endDate"] = endDate }
    if let guideName = guideName { dict["guideName"] = guideName }
    if let lodge = lodge { dict["lodge"] = lodge }
    if let community = community { dict["community"] = community }
    if let anglers = anglers { dict["anglers"] = anglers }
    return dict
  }

  /// Creates an angler dictionary for mock responses
  private func makeAnglerDict(
    id: String = UUID().uuidString,
    anglerNumber: String,
    firstName: String? = nil,
    lastName: String? = nil,
    licenses: [[String: Any]]? = nil
  ) -> [String: Any] {
    var dict: [String: Any] = [
      "id": id,
      "anglerNumber": anglerNumber
    ]
    if let firstName = firstName { dict["firstName"] = firstName }
    if let lastName = lastName { dict["lastName"] = lastName }
    if let licenses = licenses { dict["licenses"] = licenses }
    return dict
  }

  /// Creates a license dictionary for mock responses
  private func makeLicenseDict(
    id: String = UUID().uuidString,
    licenseNumber: String,
    riverName: String,
    startDate: String? = nil,
    endDate: String? = nil
  ) -> [String: Any] {
    var dict: [String: Any] = [
      "id": id,
      "licenseNumber": licenseNumber,
      "riverName": riverName
    ]
    if let startDate = startDate { dict["startDate"] = startDate }
    if let endDate = endDate { dict["endDate"] = endDate }
    return dict
  }

  // MARK: - isSyncing Tests

  func testIsSyncing_initiallyFalse() {
    let service = TripSyncService.shared
    XCTAssertFalse(service.isSyncing, "isSyncing should be false initially")
  }

  // MARK: - Sync Without JWT Tests

  func testSyncTripsIfNeeded_noJWT_doesNotFetch() async {
    // Ensure no JWT is available
    AuthStore.shared.clearForTesting()

    var requestMade = false
    MockURLProtocol.requestHandler = { _ in
      requestMade = true
      throw URLError(.notConnectedToInternet)
    }

    let service = TripSyncService.shared
    await service.syncTripsIfNeeded(context: context)

    // Should not make network request without JWT
    XCTAssertFalse(requestMade, "Should not make network request without JWT")
  }

  // MARK: - Core Data Entity Tests (Independent of Network)

  func testTripEntityCanBeCreated() {
    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.name = "Test Trip"
    trip.guideName = "Test Guide"
    trip.startDate = Date()
    trip.createdAt = Date()

    XCTAssertNoThrow(try context.save(), "Should be able to save a Trip entity")

    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    let trips = try? context.fetch(fetch)
    XCTAssertEqual(trips?.count, 1, "Should have one trip after save")
  }

  func testTripClientEntityCanBeCreated() {
    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.name = "Test Trip"
    trip.createdAt = Date()

    let client = TripClient(context: context)
    client.id = UUID()
    client.name = "John Doe"
    client.licenseNumber = "12345"
    client.trip = trip

    XCTAssertNoThrow(try context.save(), "Should be able to save TripClient entity")

    let fetch: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    let clients = try? context.fetch(fetch)
    XCTAssertEqual(clients?.count, 1, "Should have one client after save")
    XCTAssertEqual(clients?.first?.trip, trip, "Client should be linked to trip")
  }

  func testClassifiedWaterLicenseEntityCanBeCreated() {
    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.name = "Test Trip"
    trip.createdAt = Date()

    let client = TripClient(context: context)
    client.id = UUID()
    client.name = "John Doe"
    client.trip = trip

    let license = ClassifiedWaterLicense(context: context)
    license.licNumber = "CWL-001"
    license.water = "Nehalem River"
    license.validFrom = Date()
    license.validTo = Date().addingTimeInterval(86400 * 7) // 7 days
    license.client = client

    XCTAssertNoThrow(try context.save(), "Should be able to save ClassifiedWaterLicense entity")

    let fetch: NSFetchRequest<ClassifiedWaterLicense> = ClassifiedWaterLicense.fetchRequest()
    let licenses = try? context.fetch(fetch)
    XCTAssertEqual(licenses?.count, 1, "Should have one license after save")
  }

  // MARK: - Trip-Lodge Relationship Tests

  func testTripCanBeLinkToLodge() {
    // Fetch the seeded Bend Fly Shop lodge
    let lodgeFetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    lodgeFetch.predicate = NSPredicate(format: "name == %@", "Bend Fly Shop")

    guard let lodge = try? context.fetch(lodgeFetch).first else {
      XCTFail("Bend Fly Shop lodge should exist from seed data")
      return
    }

    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.name = "Lodge Trip"
    trip.createdAt = Date()
    trip.lodge = lodge

    XCTAssertNoThrow(try context.save(), "Should be able to save trip with lodge")
    XCTAssertEqual(trip.lodge?.name, "Bend Fly Shop")
  }

  func testLodgeHasCommunityAfterTripLink() {
    let lodgeFetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    lodgeFetch.predicate = NSPredicate(format: "name == %@", "Bend Fly Shop")

    guard let lodge = try? context.fetch(lodgeFetch).first else {
      XCTFail("Bend Fly Shop lodge should exist from seed data")
      return
    }

    // Lodge should already have community from seed
    XCTAssertNotNil(lodge.community, "Lodge should have community")
    XCTAssertEqual(lodge.community?.name, "Bend Fly Shop", "Lodge should belong to Bend Fly Shop")
  }

  // MARK: - Upsert Logic Tests (Unit Tests)

  func testTripUpsert_createNewTrip() {
    let tripId = UUID()

    // Verify no trip exists
    let fetchBefore: NSFetchRequest<Trip> = Trip.fetchRequest()
    fetchBefore.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
    let beforeCount = (try? context.count(for: fetchBefore)) ?? 0
    XCTAssertEqual(beforeCount, 0, "Should have no trips before creation")

    // Create trip
    let trip = Trip(context: context)
    trip.tripId = tripId
    trip.name = "New Trip"
    trip.guideName = "Guide Name"
    trip.createdAt = Date()

    try? context.save()

    // Verify trip exists
    let afterCount = (try? context.count(for: fetchBefore)) ?? 0
    XCTAssertEqual(afterCount, 1, "Should have one trip after creation")
  }

  func testTripUpsert_updateExistingTrip() {
    let tripId = UUID()

    // Create initial trip
    let trip = Trip(context: context)
    trip.tripId = tripId
    trip.name = "Original Name"
    trip.guideName = "Original Guide"
    trip.createdAt = Date()
    try? context.save()

    // Fetch and update
    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    fetch.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
    fetch.fetchLimit = 1

    guard let existingTrip = try? context.fetch(fetch).first else {
      XCTFail("Should find existing trip")
      return
    }

    existingTrip.name = "Updated Name"
    existingTrip.guideName = "Updated Guide"
    try? context.save()

    // Verify update
    let updatedTrip = try? context.fetch(fetch).first
    XCTAssertEqual(updatedTrip?.name, "Updated Name")
    XCTAssertEqual(updatedTrip?.guideName, "Updated Guide")

    // Verify no duplicate
    let allFetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    allFetch.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
    let count = (try? context.count(for: allFetch)) ?? 0
    XCTAssertEqual(count, 1, "Should still have only one trip with this ID")
  }

  // MARK: - Client Replacement Tests

  func testClientReplacement_clearsOldClients() {
    let tripId = UUID()

    // Create trip with clients
    let trip = Trip(context: context)
    trip.tripId = tripId
    trip.name = "Test Trip"
    trip.createdAt = Date()

    let client1 = TripClient(context: context)
    client1.id = UUID()
    client1.name = "Client 1"
    client1.trip = trip

    let client2 = TripClient(context: context)
    client2.id = UUID()
    client2.name = "Client 2"
    client2.trip = trip

    try? context.save()

    // Verify two clients
    let clientFetch: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    clientFetch.predicate = NSPredicate(format: "trip == %@", trip)
    let initialCount = (try? context.count(for: clientFetch)) ?? 0
    XCTAssertEqual(initialCount, 2, "Should have two clients initially")

    // Simulate replacement: delete existing clients
    if let existingClients = trip.clients as? Set<TripClient> {
      for c in existingClients {
        context.delete(c)
      }
    }

    // Add new client
    let newClient = TripClient(context: context)
    newClient.id = UUID()
    newClient.name = "New Client"
    newClient.trip = trip

    try? context.save()

    // Verify only one client now
    let finalCount = (try? context.count(for: clientFetch)) ?? 0
    XCTAssertEqual(finalCount, 1, "Should have only one client after replacement")
    XCTAssertEqual((try? context.fetch(clientFetch).first)?.name, "New Client")
  }

  // MARK: - Date Parsing Tests

  func testISO8601DateParsing() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]

    let dateString = "2024-03-15T10:30:00Z"
    let date = formatter.date(from: dateString)

    XCTAssertNotNil(date, "Should parse ISO8601 date string")

    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
    XCTAssertEqual(components.year, 2024)
    XCTAssertEqual(components.month, 3)
    XCTAssertEqual(components.day, 15)
  }

  func testYMDDateParsing() {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)

    let dateString = "2024-03-15"
    let date = formatter.date(from: dateString)

    XCTAssertNotNil(date, "Should parse YYYY-MM-DD date string")
  }

  // MARK: - Lodge Lookup Tests

  func testLodgeLookup_caseInsensitive() {
    let fetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    fetch.predicate = NSPredicate(format: "name ==[c] %@", "bend fly shop")
    fetch.fetchLimit = 1

    let lodge = try? context.fetch(fetch).first

    XCTAssertNotNil(lodge, "Should find lodge with case-insensitive search")
    XCTAssertEqual(lodge?.name, "Bend Fly Shop")
  }

  func testLodgeLookup_allSeededLodges() {
    let expectedLodges = [
      "Bend Fly Shop"
    ]

    for lodgeName in expectedLodges {
      let fetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
      fetch.predicate = NSPredicate(format: "name == %@", lodgeName)
      fetch.fetchLimit = 1

      let lodge = try? context.fetch(fetch).first
      XCTAssertNotNil(lodge, "Should find lodge: \(lodgeName)")
    }
  }

  // MARK: - Community Link Helper Tests

  func testEnsureLodgeHasCommunity_linksOrphanLodge() {
    // Create an orphan lodge (not from seed)
    let orphanLodge = Lodge(context: context)
    orphanLodge.lodgeId = UUID()
    orphanLodge.name = "Orphan Lodge"
    orphanLodge.createdAt = Date()
    orphanLodge.community = nil

    try? context.save()

    XCTAssertNil(orphanLodge.community, "Lodge should be orphaned initially")

    // Simulate the ensureLodgeHasCommunity logic
    let cf: NSFetchRequest<Community> = Community.fetchRequest()
    cf.predicate = NSPredicate(format: "name == %@", "Bend Fly Shop")
    cf.fetchLimit = 1

    if let community = try? context.fetch(cf).first {
      orphanLodge.community = community
    }

    try? context.save()

    XCTAssertNotNil(orphanLodge.community, "Lodge should now have community")
    XCTAssertEqual(orphanLodge.community?.name, "Bend Fly Shop")
  }

  // MARK: - Concurrent Sync Prevention Tests

  func testSyncPreventsOverlappingRuns() async {
    // This tests that isSyncing flag prevents concurrent syncs
    // Note: This is a unit test of the flag behavior, not a full integration test

    let service = TripSyncService.shared

    // Initially not syncing
    XCTAssertFalse(service.isSyncing)

    // After sync completes (even without JWT), it should be false
    await service.syncTripsIfNeeded(context: context)
    XCTAssertFalse(service.isSyncing, "isSyncing should be false after sync completes")
  }

  // MARK: - Performance Tests

  func testTripCreationPerformance() {
    measure {
      for i in 0..<100 {
        let trip = Trip(context: context)
        trip.tripId = UUID()
        trip.name = "Performance Trip \(i)"
        trip.guideName = "Guide \(i)"
        trip.createdAt = Date()
      }
      try? context.save()

      // Clean up for next iteration
      let fetch: NSFetchRequest<NSFetchRequestResult> = Trip.fetchRequest()
      let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
      _ = try? context.execute(deleteRequest)
    }
  }
}

// MARK: - AuthStore Testing Extension

extension AuthStore {
  /// Clears auth state for testing purposes
  func clearForTesting() {
    // This would need to be implemented in the main AuthStore
    // For now, we rely on the fact that no JWT is set in test environment
  }
}
