import XCTest
import CoreData
@testable import SkeenaSystem

/// Tests for the orphaned trip removal logic in TripSyncService.
///
/// Validates that local trips not present on the server are deleted
/// during sync reconciliation, while trips still on the server are kept.
@MainActor
final class TripOrphanRemovalTests: XCTestCase {

  // MARK: - Properties

  private var persistenceController: PersistenceController!
  private var context: NSManagedObjectContext!

  // MARK: - Setup / Teardown

  override func setUp() {
    super.setUp()
    persistenceController = PersistenceController(inMemory: true)
    context = persistenceController.container.viewContext
  }

  override func tearDown() {
    context = nil
    persistenceController = nil
    super.tearDown()
  }

  // MARK: - Helpers

  @discardableResult
  private func createTrip(
    tripId: UUID = UUID(),
    name: String = "Test Trip",
    guideName: String = "Test Guide"
  ) -> Trip {
    let trip = Trip(context: context)
    trip.tripId = tripId
    trip.name = name
    trip.guideName = guideName
    trip.createdAt = Date()
    return trip
  }

  private func tripCount() -> Int {
    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    return (try? context.count(for: fetch)) ?? 0
  }

  private func clientCount() -> Int {
    let fetch: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    return (try? context.count(for: fetch)) ?? 0
  }

  /// Replicates the orphan removal logic from TripSyncService for testability.
  private func removeOrphanedTrips(serverTripIDs: Set<UUID>) {
    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    guard let localTrips = try? context.fetch(fetch) else { return }

    for trip in localTrips {
      guard let tripId = trip.tripId else { continue }
      if !serverTripIDs.contains(tripId) {
        context.delete(trip)
      }
    }
  }

  // MARK: - Orphan Removal Tests

  func testOrphanedTripsAreDeleted() {
    let serverTripId = UUID()
    let orphanTripId = UUID()

    createTrip(tripId: serverTripId, name: "Server Trip")
    createTrip(tripId: orphanTripId, name: "Orphan Trip")
    try? context.save()

    XCTAssertEqual(tripCount(), 2, "Should start with 2 trips")

    // Only serverTripId exists on the server
    removeOrphanedTrips(serverTripIDs: [serverTripId])
    try? context.save()

    XCTAssertEqual(tripCount(), 1, "Should have 1 trip after orphan removal")

    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    let remaining = try? context.fetch(fetch)
    XCTAssertEqual(remaining?.first?.name, "Server Trip", "The server trip should remain")
  }

  func testAllTripsKept_whenAllOnServer() {
    let id1 = UUID()
    let id2 = UUID()
    let id3 = UUID()

    createTrip(tripId: id1, name: "Trip 1")
    createTrip(tripId: id2, name: "Trip 2")
    createTrip(tripId: id3, name: "Trip 3")
    try? context.save()

    XCTAssertEqual(tripCount(), 3)

    removeOrphanedTrips(serverTripIDs: [id1, id2, id3])
    try? context.save()

    XCTAssertEqual(tripCount(), 3, "All trips should remain when all are on server")
  }

  func testAllTripsRemoved_whenNoneOnServer() {
    createTrip(name: "Trip 1")
    createTrip(name: "Trip 2")
    try? context.save()

    XCTAssertEqual(tripCount(), 2)

    removeOrphanedTrips(serverTripIDs: [])
    try? context.save()

    XCTAssertEqual(tripCount(), 0, "All trips should be removed when none are on server")
  }

  func testNoTripsLocally_handlesGracefully() {
    XCTAssertEqual(tripCount(), 0)

    removeOrphanedTrips(serverTripIDs: [UUID(), UUID()])
    try? context.save()

    XCTAssertEqual(tripCount(), 0, "Should handle empty local state gracefully")
  }

  func testOrphanRemoval_cascadesDeleteToClients() {
    let serverTripId = UUID()
    let orphanTripId = UUID()

    let serverTrip = createTrip(tripId: serverTripId, name: "Server Trip")
    let orphanTrip = createTrip(tripId: orphanTripId, name: "Orphan Trip")

    // Add clients to both trips
    let client1 = TripClient(context: context)
    client1.id = UUID()
    client1.name = "Client on Server Trip"
    client1.trip = serverTrip

    let client2 = TripClient(context: context)
    client2.id = UUID()
    client2.name = "Client on Orphan Trip"
    client2.trip = orphanTrip

    try? context.save()

    XCTAssertEqual(tripCount(), 2)
    XCTAssertEqual(clientCount(), 2)

    removeOrphanedTrips(serverTripIDs: [serverTripId])
    try? context.save()

    XCTAssertEqual(tripCount(), 1, "Orphan trip should be removed")
    XCTAssertEqual(clientCount(), 1, "Client of orphan trip should be cascade-deleted")

    let fetch: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    let remainingClients = try? context.fetch(fetch)
    XCTAssertEqual(remainingClients?.first?.name, "Client on Server Trip", "Only server trip's client should remain")
  }

  func testOrphanRemoval_multipleOrphans() {
    let serverTripId = UUID()

    createTrip(tripId: serverTripId, name: "Server Trip")
    createTrip(name: "Orphan 1")
    createTrip(name: "Orphan 2")
    createTrip(name: "Orphan 3")
    try? context.save()

    XCTAssertEqual(tripCount(), 4)

    removeOrphanedTrips(serverTripIDs: [serverTripId])
    try? context.save()

    XCTAssertEqual(tripCount(), 1, "Should remove all 3 orphans, keep 1 server trip")
  }

  func testOrphanRemoval_tripsWithNilTripId_areSkipped() {
    // Trips with nil tripId should not be deleted (guard let protects them)
    let trip = Trip(context: context)
    trip.tripId = nil
    trip.name = "Nil ID Trip"
    trip.createdAt = Date()

    let serverTripId = UUID()
    createTrip(tripId: serverTripId, name: "Server Trip")
    try? context.save()

    XCTAssertEqual(tripCount(), 2)

    removeOrphanedTrips(serverTripIDs: [serverTripId])
    try? context.save()

    // The nil-ID trip should be skipped (not deleted), server trip kept
    XCTAssertEqual(tripCount(), 2, "Trip with nil tripId should be skipped by orphan removal")
  }
}
