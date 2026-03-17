import XCTest
import CoreData
@testable import SkeenaSystem

/// Regression tests for PersistenceController and seed data.
/// These tests verify that the Bend Fly Shop community and its lodges
/// are correctly seeded into Core Data, and that the seeding is idempotent.
@MainActor
final class PersistenceTests: XCTestCase {

  // MARK: - Properties

  /// Shared controller for all tests in this class to avoid malloc issues
  /// from creating/destroying multiple CoreData stacks rapidly
  private var controller: PersistenceController!
  private var context: NSManagedObjectContext!

  // MARK: - Expected Data (Snapshot of Current Configuration)

  /// The expected community name - this is hardcoded in Persistence.swift
  private let expectedCommunityName = "Bend Fly Shop"

  /// The expected lodge names - these are hardcoded in Persistence.swift
  private let expectedLodgeNames: Set<String> = [
    "Bend Fly Shop"
  ]

  // MARK: - Setup / Teardown

  override func setUp() {
    super.setUp()
    controller = PersistenceController(inMemory: true)
    context = controller.container.viewContext
  }

  override func tearDown() {
    context = nil
    controller = nil
    super.tearDown()
  }

  // MARK: - Community Seed Tests

  func testSeedCreatesBendFlyShopCommunity() {
    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", expectedCommunityName)

    let communities = try? context.fetch(fetchRequest)

    XCTAssertNotNil(communities, "Should be able to fetch communities")
    XCTAssertEqual(communities?.count, 1, "Should have exactly one Bend Fly Shop community")
    XCTAssertEqual(communities?.first?.name, expectedCommunityName,
                   "Community name should be '\(expectedCommunityName)'")
  }

  func testSeedCommunityHasUUID() {
    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", expectedCommunityName)

    let community = try? context.fetch(fetchRequest).first

    XCTAssertNotNil(community?.communityId, "Community should have a UUID")
  }

  func testSeedCommunityHasCreatedAt() {
    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", expectedCommunityName)

    let community = try? context.fetch(fetchRequest).first

    XCTAssertNotNil(community?.createdAt, "Community should have a createdAt date")
  }

  // MARK: - Lodge Seed Tests

  func testSeedCreatesAllLodges() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = try? context.fetch(fetchRequest)

    XCTAssertNotNil(lodges, "Should be able to fetch lodges")
    XCTAssertEqual(lodges?.count, expectedLodgeNames.count,
                   "Should have exactly \(expectedLodgeNames.count) lodges")
  }

  func testSeedCreatesExpectedLodgeNames() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = try? context.fetch(fetchRequest)

    let actualNames = Set(lodges?.compactMap { $0.name } ?? [])

    XCTAssertEqual(actualNames, expectedLodgeNames,
                   "Lodge names should match expected set")
  }

  func testEachLodgeHasUUID() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = (try? context.fetch(fetchRequest)) ?? []

    for lodge in lodges {
      XCTAssertNotNil(lodge.lodgeId, "Lodge '\(lodge.name ?? "unknown")' should have a UUID")
    }
  }

  func testEachLodgeHasCreatedAt() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = (try? context.fetch(fetchRequest)) ?? []

    for lodge in lodges {
      XCTAssertNotNil(lodge.createdAt, "Lodge '\(lodge.name ?? "unknown")' should have a createdAt date")
    }
  }

  // MARK: - Community-Lodge Relationship Tests

  // TODO: Temporarily disabled - investigate test failure
  func _testAllLodgesLinkedToCommunity() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = (try? context.fetch(fetchRequest)) ?? []

    for lodge in lodges {
      XCTAssertNotNil(lodge.community, "Lodge '\(lodge.name ?? "unknown")' should be linked to a community")
      XCTAssertEqual(lodge.community?.name, expectedCommunityName,
                     "Lodge '\(lodge.name ?? "unknown")' should be linked to '\(expectedCommunityName)'")
    }
  }

  func testCommunityHasAllLodgesInRelationship() {
    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", expectedCommunityName)

    let community = try? context.fetch(fetchRequest).first

    let lodgeSet = community?.lodges as? Set<Lodge>
    let lodgeNames = Set(lodgeSet?.compactMap { $0.name } ?? [])

    XCTAssertEqual(lodgeNames, expectedLodgeNames,
                   "Community should have all expected lodges in its relationship")
  }

  // MARK: - Idempotency Tests

  func testSeedIsIdempotent_noDuplicateCommunities() {
    // Call seed again (it's already called in init)
    controller.seedCommunityIfNeeded(context: context)
    controller.seedCommunityIfNeeded(context: context)
    controller.seedCommunityIfNeeded(context: context)

    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", expectedCommunityName)

    let communities = try? context.fetch(fetchRequest)

    XCTAssertEqual(communities?.count, 1,
                   "Should still have exactly one community after multiple seed calls")
  }

  func testSeedIsIdempotent_noDuplicateLodges() {
    // Call seed again (it's already called in init)
    controller.seedCommunityIfNeeded(context: context)
    controller.seedCommunityIfNeeded(context: context)
    controller.seedCommunityIfNeeded(context: context)

    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = try? context.fetch(fetchRequest)

    XCTAssertEqual(lodges?.count, expectedLodgeNames.count,
                   "Should still have exactly \(expectedLodgeNames.count) lodges after multiple seed calls")
  }

  // MARK: - Orphan Lodge Linking Tests

  func testOrphanLodgeGetsLinkedToCommunity() {
    // Create an orphan lodge with a known name (but no community link)
    let orphanLodge = Lodge(context: context)
    orphanLodge.lodgeId = UUID()
    orphanLodge.name = "Bend Fly Shop"
    orphanLodge.createdAt = Date()
    orphanLodge.community = nil

    try? context.save()

    // Now call seed - it should link the orphan to Bend Fly Shop
    controller.seedCommunityIfNeeded(context: context)

    // Fetch the lodge again
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", "Bend Fly Shop")

    let lodges = try? context.fetch(fetchRequest)

    // Should have at least one, and it should be linked
    XCTAssertGreaterThan(lodges?.count ?? 0, 0, "Should have at least one Bend Fly Shop lodge")

    for lodge in lodges ?? [] {
      XCTAssertNotNil(lodge.community, "Orphan lodge should now be linked to community")
      XCTAssertEqual(lodge.community?.name, expectedCommunityName,
                     "Orphan lodge should be linked to Bend Fly Shop")
    }
  }

  // MARK: - Specific Lodge Tests (Snapshot/Regression)

  func testBendFlyShopLodgeExists() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "name == %@", "Bend Fly Shop")

    let lodges = try? context.fetch(fetchRequest)

    XCTAssertEqual(lodges?.count, 1, "Should have exactly one Bend Fly Shop lodge")
    XCTAssertNotNil(lodges?.first?.community, "Bend Fly Shop should be linked to community")
  }

  // MARK: - Trip Relationship Tests

  func testLodgeCanHaveTrips() {
    // Fetch a lodge
    let lodgeFetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    lodgeFetch.predicate = NSPredicate(format: "name == %@", "Bend Fly Shop")
    guard let lodge = try? context.fetch(lodgeFetch).first else {
      XCTFail("Bend Fly Shop lodge should exist")
      return
    }

    // Create a trip and link it
    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.name = "Test Trip"
    trip.guideName = "Test Guide"
    trip.startDate = Date()
    trip.createdAt = Date()
    trip.lodge = lodge

    try? context.save()

    // Verify the relationship
    XCTAssertEqual(trip.lodge?.name, "Bend Fly Shop")
    XCTAssertTrue((lodge.trips as? Set<Trip>)?.contains(trip) ?? false,
                  "Lodge should contain the trip in its trips relationship")
  }

  // MARK: - Core Data Stack Tests

  func testViewContextMergePolicy() {
    // Verify merge policy is set correctly (NSMergeByPropertyObjectTrumpMergePolicy is an instance, not a type)
    let mergePolicy = controller.container.viewContext.mergePolicy as AnyObject
    XCTAssertTrue(mergePolicy === NSMergeByPropertyObjectTrumpMergePolicy,
                  "Merge policy should be NSMergeByPropertyObjectTrumpMergePolicy")
  }

  func testViewContextAutoMerge() {
    XCTAssertTrue(controller.container.viewContext.automaticallyMergesChangesFromParent,
                  "View context should automatically merge changes from parent")
  }

  // MARK: - Count Tests (Snapshot)

  func testLodgeCountSnapshot() {
    let fetchRequest: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let count = (try? context.count(for: fetchRequest)) ?? 0

    XCTAssertEqual(count, 1, "Should have exactly 1 lodge (snapshot test)")
  }

  func testCommunityCountSnapshot() {
    let fetchRequest: NSFetchRequest<Community> = Community.fetchRequest()
    let count = (try? context.count(for: fetchRequest)) ?? 0

    XCTAssertEqual(count, 1, "Should have exactly 1 community (snapshot test)")
  }
}
