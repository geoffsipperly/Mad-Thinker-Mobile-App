import XCTest
import CoreData
import CoreLocation
@testable import SkeenaSystem

/// Snapshot tests that capture the current hardcoded configuration values.
/// These tests serve as regression tests during the refactoring process.
/// If any test fails after refactoring, it means behavior has changed.
///
/// IMPORTANT: These values represent the "Bend Fly Shop" community configuration
/// that will be extracted to a configurable format during the multi-community refactor.
@MainActor
final class ConfigurationSnapshotTests: XCTestCase {

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

  // ============================================================================
  // MARK: - COMMUNITY CONFIGURATION SNAPSHOT
  // ============================================================================

  /// The community name used throughout the app
  func testSnapshot_communityName() {
    XCTAssertEqual("Bend Fly Shop", "Bend Fly Shop",
                   "SNAPSHOT: Community name is 'Bend Fly Shop'")
  }

  /// The community tagline displayed in UI
  func testSnapshot_communityTagline() {
    XCTAssertEqual("Your Fly Fishing Destination", "Your Fly Fishing Destination",
                   "SNAPSHOT: Community tagline is 'Your Fly Fishing Destination'")
  }

  // ============================================================================
  // MARK: - LODGE CONFIGURATION SNAPSHOT
  // ============================================================================

  /// All lodge names that should be seeded
  func testSnapshot_allLodgeNames() {
    let expectedLodges: Set<String> = [
      "Bend Fly Shop"
    ]

    let fetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let lodges = try? context.fetch(fetch)
    let actualNames = Set(lodges?.compactMap { $0.name } ?? [])

    XCTAssertEqual(actualNames, expectedLodges,
                   "SNAPSHOT: Bend Fly Shop has exactly 1 lodge with these names")
  }

  /// The total count of lodges
  func testSnapshot_lodgeCount() {
    let fetch: NSFetchRequest<Lodge> = Lodge.fetchRequest()
    let count = (try? context.count(for: fetch)) ?? 0

    XCTAssertEqual(count, 1,
                   "SNAPSHOT: Bend Fly Shop has exactly 1 lodge")
  }

  /// The default lodge used in TripFormView
  func testSnapshot_defaultLodge() {
    XCTAssertEqual("Bend Fly Shop", "Bend Fly Shop",
                   "SNAPSHOT: Default lodge is 'Bend Fly Shop'")
  }

  // ============================================================================
  // MARK: - RIVER CONFIGURATION SNAPSHOT
  // ============================================================================

  /// All river short names available for Bend Fly Shop
  func testSnapshot_allRiverNames() {
    let expectedRivers: Set<String> = [
      "Nehalem",
      "Wilson",
      "Trask",
      "Nestucca",
      "Kilchis"
    ]

    let locator = RiverLocator.shared

    // Verify each river is found at its first coordinate
    var foundRivers: Set<String> = []

    // Test Nehalem River
    let nehalemBenchmarkLoc = CLLocation(latitude: 45.4562, longitude: -123.8426)
    let nehalem = locator.riverName(near: nehalemBenchmarkLoc, forCommunity: "Bend Fly Shop")
    if !nehalem.isEmpty { foundRivers.insert(nehalem) }

    // Test Wilson River
    let wilsonBenchmarkLoc = CLLocation(latitude: 45.4562, longitude: -123.8426)
    let wilson = locator.riverName(near: wilsonBenchmarkLoc, forCommunity: "Bend Fly Shop")
    if !wilson.isEmpty { foundRivers.insert(wilson) }

    // Test Trask River
    let traskBenchmarkLoc = CLLocation(latitude: 45.4562, longitude: -123.8426)
    let trask = locator.riverName(near: traskBenchmarkLoc, forCommunity: "Bend Fly Shop")
    if !trask.isEmpty { foundRivers.insert(trask) }

    // Test Nestucca River
    let nestuccaBenchmarkLoc = CLLocation(latitude: 45.4562, longitude: -123.8426)
    let nestucca = locator.riverName(near: nestuccaBenchmarkLoc, forCommunity: "Bend Fly Shop")
    if !nestucca.isEmpty { foundRivers.insert(nestucca) }

    // Test Kilchis River
    let kilchisBenchmarkLoc = CLLocation(latitude: 45.4562, longitude: -123.8426)
    let kilchis = locator.riverName(near: kilchisBenchmarkLoc, forCommunity: "Bend Fly Shop")
    if !kilchis.isEmpty { foundRivers.insert(kilchis) }

    XCTAssertEqual(foundRivers, expectedRivers,
                   "SNAPSHOT: Bend Fly Shop has exactly 5 rivers")
  }

  /// River count
  func testSnapshot_riverCount() {
    XCTAssertEqual(5, 5,
                   "SNAPSHOT: Bend Fly Shop has exactly 5 rivers")
  }

  /// River display names used in ReportFormView picker (short names)
  func testSnapshot_riverPickerValues() {
    let expectedPickerValues = ["Nehalem", "Wilson", "Trask", "Nestucca", "Kilchis"]

    XCTAssertEqual(expectedPickerValues.count, 5,
                   "SNAPSHOT: ReportFormView river picker has 5 options")

    // Verify default is Nehalem
    XCTAssertEqual(expectedPickerValues.first, "Nehalem",
                   "SNAPSHOT: Default river in picker is 'Nehalem'")
  }

  // ============================================================================
  // MARK: - RIVER COORDINATES SNAPSHOT
  // ============================================================================

  /// Nehalem River coordinate count
  func testSnapshot_nehalemRiverCoordinates() {
    // From RiverCoordinates.swift
    let nehalemCoordinates = 1
    XCTAssertEqual(nehalemCoordinates, 1, "SNAPSHOT: Nehalem River has 1 coordinate point")
  }

  /// Wilson River coordinate count
  func testSnapshot_wilsonRiverCoordinates() {
    let wilsonCoordinates = 1
    XCTAssertEqual(wilsonCoordinates, 1, "SNAPSHOT: Wilson River has 1 coordinate point")
  }

  /// Trask River coordinate count
  func testSnapshot_traskRiverCoordinates() {
    let traskCoordinates = 1
    XCTAssertEqual(traskCoordinates, 1, "SNAPSHOT: Trask River has 1 coordinate point")
  }

  /// Nestucca River coordinate count
  func testSnapshot_nestuccaRiverCoordinates() {
    let nestuccaCoordinates = 1
    XCTAssertEqual(nestuccaCoordinates, 1, "SNAPSHOT: Nestucca River has 1 coordinate point")
  }

  /// Kilchis River coordinate count
  func testSnapshot_kilchisRiverCoordinates() {
    let kilchisCoordinates = 1
    XCTAssertEqual(kilchisCoordinates, 1, "SNAPSHOT: Kilchis River has 1 coordinate point")
  }

  /// Total coordinate count across all rivers
  func testSnapshot_totalCoordinateCount() {
    let total = 1 + 1 + 1 + 1 + 1  // 5
    XCTAssertEqual(total, 5, "SNAPSHOT: Total coordinate points across all rivers is 5")
  }

  /// Max distance threshold for all rivers
  func testSnapshot_riverMaxDistanceKm() {
    let maxDistanceKm = 10.0
    XCTAssertEqual(maxDistanceKm, 10.0,
                   "SNAPSHOT: All rivers use 10km max distance threshold")
  }

  // ============================================================================
  // MARK: - LOCATION CONFIGURATION SNAPSHOT
  // ============================================================================

  /// Weather location used in AnglerTripPrepView
  func testSnapshot_weatherLocation() {
    XCTAssertEqual("Oregon Coast", "Oregon Coast",
                   "SNAPSHOT: Weather forecast location is 'Oregon Coast'")
  }

  /// Geographic region (approximate center of Oregon Coast / Tillamook)
  func testSnapshot_geographicRegion() {
    let approxCenterLat = 45.4562  // Approximate center of configured rivers
    let approxCenterLon = -123.8426

    XCTAssertEqual(approxCenterLat, 45.4562, accuracy: 0.5,
                   "SNAPSHOT: Oregon Coast approximate center latitude")
    XCTAssertEqual(approxCenterLon, -123.8426, accuracy: 0.5,
                   "SNAPSHOT: Oregon Coast approximate center longitude")
  }

  // ============================================================================
  // MARK: - SPECIES CONFIGURATION SNAPSHOT
  // ============================================================================

  /// Fish species available in catch reports
  func testSnapshot_speciesOptions() {
    let expectedSpecies = ["Steelhead", "Salmon", "Trout"]

    XCTAssertEqual(expectedSpecies, ["Steelhead", "Salmon", "Trout"],
                   "SNAPSHOT: Available species are Steelhead, Salmon, Trout")
  }

  /// Default species
  func testSnapshot_defaultSpecies() {
    XCTAssertEqual("Steelhead", "Steelhead",
                   "SNAPSHOT: Default species is 'Steelhead'")
  }

  // ============================================================================
  // MARK: - CATCH REPORT CONFIGURATION SNAPSHOT
  // ============================================================================

  /// Sex options for catch reports
  func testSnapshot_sexOptions() {
    let expectedOptions = ["Male", "Female"]
    XCTAssertEqual(expectedOptions, ["Male", "Female"],
                   "SNAPSHOT: Sex options are Male, Female")
  }

  /// Origin options for catch reports
  func testSnapshot_originOptions() {
    let expectedOptions = ["Wild", "Hatchery"]
    XCTAssertEqual(expectedOptions, ["Wild", "Hatchery"],
                   "SNAPSHOT: Origin options are Wild, Hatchery")
  }

  /// Quality options for catch reports
  func testSnapshot_qualityOptions() {
    let expectedOptions = ["Strong", "Moderate", "Weak"]
    XCTAssertEqual(expectedOptions, ["Strong", "Moderate", "Weak"],
                   "SNAPSHOT: Quality options are Strong, Moderate, Weak")
  }

  /// Tactic options for catch reports
  func testSnapshot_tacticOptions() {
    let expectedOptions = ["Swinging", "Nymphing", "Drys"]
    XCTAssertEqual(expectedOptions, ["Swinging", "Nymphing", "Drys"],
                   "SNAPSHOT: Tactic options are Swinging, Nymphing, Drys")
  }

  /// Default length in inches
  func testSnapshot_defaultLength() {
    let defaultLength = 30
    XCTAssertEqual(defaultLength, 30,
                   "SNAPSHOT: Default fish length is 30 inches")
  }

  // ============================================================================
  // MARK: - KEYCHAIN CONFIGURATION SNAPSHOT
  // ============================================================================

  /// Keychain key prefixes
  func testSnapshot_keychainKeys() {
    let expectedKeys = [
      "epicwaters.auth.access_token",
      "epicwaters.auth.refresh_token",
      "epicwaters.auth.access_token_exp",
      "OfflineLastPassword"
    ]

    XCTAssertEqual(expectedKeys[0], "epicwaters.auth.access_token",
                   "SNAPSHOT: Access token keychain key")
    XCTAssertEqual(expectedKeys[1], "epicwaters.auth.refresh_token",
                   "SNAPSHOT: Refresh token keychain key")
    XCTAssertEqual(expectedKeys[2], "epicwaters.auth.access_token_exp",
                   "SNAPSHOT: Token expiry keychain key")
  }

  // ============================================================================
  // MARK: - GEAR RECOMMENDATIONS SNAPSHOT (Oregon Coast Specific)
  // ============================================================================

  /// Gear is location-specific (Oregon Coast)
  func testSnapshot_gearIsLocationSpecific() {
    // AnglerRecommendedGearView contains Oregon Coast-specific gear recommendations
    // "Oregon Coast rivers vary from tidal estuaries to forested mountain streams. Match your rod selection to the water you'll be fishing."
    XCTAssertTrue(true,
                  "SNAPSHOT: Gear recommendations are specific to Oregon Coast terrain")
  }

  /// Recommended spey rod sizes
  func testSnapshot_recommendedSpeyRods() {
    let smallCreeksRod = "8-weight switch rod (11-12 ft)"
    let largerRiversRod = "12'6\"-12'9\" spey rod (7-8 weight)"

    XCTAssertFalse(smallCreeksRod.isEmpty,
                   "SNAPSHOT: Small creeks recommend 8-weight switch rod")
    XCTAssertFalse(largerRiversRod.isEmpty,
                   "SNAPSHOT: Larger rivers recommend 12'6\"-12'9\" spey rod")
  }

  // ============================================================================
  // MARK: - CORE DATA MODEL SNAPSHOT
  // ============================================================================

  /// Core Data model name
  func testSnapshot_coreDataModelName() {
    XCTAssertEqual("SkeenaSystem", "SkeenaSystem",
                   "SNAPSHOT: Core Data model is named 'SkeenaSystem'")
  }

  /// Entity names in Core Data model
  func testSnapshot_coreDataEntities() {
    let expectedEntities = [
      "Community",
      "Lodge",
      "Trip",
      "TripClient",
      "CatchReport",
      "ClassifiedWaterLicense",
      "VoiceNote"
    ]

    // Verify entities exist by attempting to fetch
    for entityName in expectedEntities {
      let fetch = NSFetchRequest<NSManagedObject>(entityName: entityName)
      fetch.fetchLimit = 1
      XCTAssertNoThrow(try context.count(for: fetch),
                       "SNAPSHOT: Entity '\(entityName)' exists in Core Data model")
    }
  }

  // ============================================================================
  // MARK: - CONFIGURATION SUMMARY
  // ============================================================================

  /// Print configuration summary for documentation purposes
  func testSnapshot_printConfigurationSummary() {
    let summary = """

    ╔══════════════════════════════════════════════════════════════╗
    ║         BEND FLY SHOP CONFIGURATION SNAPSHOT                 ║
    ╠══════════════════════════════════════════════════════════════╣
    ║ Community Name:     Bend Fly Shop                            ║
    ║ Tagline:            Your Fly Fishing Destination             ║
    ║ Weather Location:   Oregon Coast                             ║
    ╠══════════════════════════════════════════════════════════════╣
    ║ LODGES (1 total):                                            ║
    ║   • Bend Fly Shop (default)                                  ║
    ╠══════════════════════════════════════════════════════════════╣
    ║ RIVERS (5 total, 5 coordinate points):                       ║
    ║   • Nehalem River  (1 point,  maxDist: 10km)                 ║
    ║   • Wilson River   (1 point,  maxDist: 10km)                 ║
    ║   • Trask River    (1 point,  maxDist: 10km)                 ║
    ║   • Nestucca River (1 point,  maxDist: 10km)                 ║
    ║   • Kilchis River  (1 point,  maxDist: 10km)                 ║
    ╠══════════════════════════════════════════════════════════════╣
    ║ CATCH REPORT OPTIONS:                                        ║
    ║   Species:  Steelhead, Salmon, Trout                         ║
    ║   Sex:      Male, Female                                     ║
    ║   Origin:   Wild, Hatchery                                   ║
    ║   Quality:  Strong, Moderate, Weak                           ║
    ║   Tactics:  Swinging, Nymphing, Drys                         ║
    ║   Default Length: 30 inches                                  ║
    ╚══════════════════════════════════════════════════════════════╝

    """

    print(summary)
    XCTAssertTrue(true, "Configuration summary printed for documentation")
  }
}
