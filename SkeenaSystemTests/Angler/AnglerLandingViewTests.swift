// AnglerLandingViewTests.swift
// SkeenaSystemTests
//
// Unit tests for the AnglerLandingView logic: ISO date parsing, date
// formatting, report sorting/display, DownloadResponse decoding, and
// angler-type routing.

import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class AnglerLandingViewTests: XCTestCase {

  // MARK: - Setup / teardown

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    AuthService.resetSharedForTests()
    clearAuthKeychainEntries()
  }

  override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    clearAuthKeychainEntries()
    super.tearDown()
  }

  private func clearAuthKeychainEntries() {
    let keys = [
      "epicwaters.auth.access_token",
      "epicwaters.auth.refresh_token",
      "epicwaters.auth.access_token_exp",
      "OfflineLastPassword"
    ]
    for account in keys {
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: account
      ]
      SecItemDelete(query as CFDictionary)
    }
  }

  // MARK: - ISO Date Parsing (replicates AnglerLandingView.parseISO)

  /// Mirrors the private parseISO logic from AnglerLandingView.
  private static func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }

  /// Mirrors the private fmtDate logic from AnglerLandingView.
  private static func fmtDate(_ iso: String) -> String {
    if let d = parseISO(iso) {
      let f = DateFormatter()
      f.dateStyle = .medium; f.timeStyle = .short
      return f.string(from: d)
    }
    return iso
  }

  func testParseISO_withFractionalSeconds() {
    let date = Self.parseISO("2026-01-15T10:30:00.123Z")
    XCTAssertNotNil(date, "Should parse ISO 8601 with fractional seconds")
  }

  func testParseISO_withoutFractionalSeconds() {
    let date = Self.parseISO("2026-01-15T10:30:00Z")
    XCTAssertNotNil(date, "Should parse ISO 8601 without fractional seconds via fallback")
  }

  func testParseISO_invalidString_returnsNil() {
    let date = Self.parseISO("not-a-date")
    XCTAssertNil(date, "Invalid date strings should return nil")
  }

  func testParseISO_emptyString_returnsNil() {
    let date = Self.parseISO("")
    XCTAssertNil(date, "Empty string should return nil")
  }

  func testParseISO_withTimezone() {
    let date = Self.parseISO("2026-06-01T08:00:00+05:00")
    XCTAssertNotNil(date, "Should parse ISO 8601 with timezone offset")
  }

  // MARK: - Date Formatting

  func testFmtDate_validISO_returnsFormattedString() {
    let result = Self.fmtDate("2026-01-15T10:30:00Z")
    XCTAssertFalse(result.isEmpty, "Formatted date should not be empty")
    XCTAssertNotEqual(result, "2026-01-15T10:30:00Z", "Should transform the ISO string into a human-readable format")
  }

  func testFmtDate_invalidISO_returnsOriginal() {
    let original = "not-a-date"
    let result = Self.fmtDate(original)
    XCTAssertEqual(result, original, "Invalid ISO strings should be returned unchanged")
  }

  // MARK: - Report Sorting (replicates AnglerLandingView.sortedReports)

  private func sortReports(_ reports: [CatchReportDTO]) -> [CatchReportDTO] {
    reports.sorted {
      let d0 = Self.parseISO($0.createdAt) ?? .distantPast
      let d1 = Self.parseISO($1.createdAt) ?? .distantPast
      return d0 > d1
    }
  }

  private func makeSampleReports() -> [CatchReportDTO] {
    let json = """
    {
      "catch_reports": [
        {"catch_id":"c1","created_at":"2026-01-10T08:00:00Z","river":"Skeena","latitude":54.0,"longitude":-128.0,"photo_url":null,"notes":null},
        {"catch_id":"c3","created_at":"2026-01-20T12:00:00Z","river":"Copper","latitude":54.1,"longitude":-128.1,"photo_url":"https://example.com/photo.jpg","notes":"Big one"},
        {"catch_id":"c2","created_at":"2026-01-15T10:30:00.500Z","river":"Nehalem","latitude":null,"longitude":null,"photo_url":null,"notes":null}
      ]
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(DownloadResponse.self, from: json).catch_reports
  }

  func testSortedReports_newestFirst() {
    let reports = makeSampleReports()
    let sorted = sortReports(reports)

    XCTAssertEqual(sorted[0].catch_id, "c3", "Most recent report should be first")
    XCTAssertEqual(sorted[1].catch_id, "c2", "Middle report should be second")
    XCTAssertEqual(sorted[2].catch_id, "c1", "Oldest report should be last")
  }

  func testSortedReports_emptyArray() {
    let sorted = sortReports([])
    XCTAssertTrue(sorted.isEmpty, "Sorting an empty array should return empty")
  }

  func testSortedReports_singleReport() {
    let json = """
    {"catch_reports":[{"catch_id":"only","created_at":"2026-01-01T00:00:00Z","river":"Test","latitude":null,"longitude":null,"photo_url":null,"notes":null}]}
    """.data(using: .utf8)!
    let reports = try! JSONDecoder().decode(DownloadResponse.self, from: json).catch_reports
    let sorted = sortReports(reports)

    XCTAssertEqual(sorted.count, 1)
    XCTAssertEqual(sorted[0].catch_id, "only")
  }

  // MARK: - Display Limiting (replicates displayedReports / hasMore)

  func testDisplayedReports_limitsToTwo_whenShowAllFalse() {
    let reports = sortReports(makeSampleReports())
    let showAll = false
    let displayed = showAll ? reports : Array(reports.prefix(2))

    XCTAssertEqual(displayed.count, 2, "Should show at most 2 reports when showAll is false")
    XCTAssertEqual(displayed[0].catch_id, "c3", "First displayed should be the newest")
    XCTAssertEqual(displayed[1].catch_id, "c2", "Second displayed should be next newest")
  }

  func testDisplayedReports_showsAll_whenShowAllTrue() {
    let reports = sortReports(makeSampleReports())
    let showAll = true
    let displayed = showAll ? reports : Array(reports.prefix(2))

    XCTAssertEqual(displayed.count, 3, "Should show all reports when showAll is true")
  }

  func testHasMore_trueWhenMoreThanTwo() {
    let reports = makeSampleReports()
    XCTAssertTrue(reports.count > 2, "hasMore should be true when there are more than 2 reports")
  }

  func testHasMore_falseWhenTwoOrFewer() {
    let json = """
    {"catch_reports":[
      {"catch_id":"c1","created_at":"2026-01-10T08:00:00Z","river":"Skeena","latitude":null,"longitude":null,"photo_url":null,"notes":null},
      {"catch_id":"c2","created_at":"2026-01-15T10:00:00Z","river":"Nehalem","latitude":null,"longitude":null,"photo_url":null,"notes":null}
    ]}
    """.data(using: .utf8)!
    let reports = try! JSONDecoder().decode(DownloadResponse.self, from: json).catch_reports
    XCTAssertFalse(reports.count > 2, "hasMore should be false when 2 or fewer reports")
  }

  // MARK: - DownloadResponse / CatchReportDTO Decoding

  func testDownloadResponseDecoding_fullPayload() throws {
    let json = """
    {
      "catch_reports": [
        {
          "catch_id": "abc-123",
          "created_at": "2026-02-01T14:30:00.000Z",
          "river": "Skeena",
          "latitude": 54.123,
          "longitude": -128.456,
          "photo_url": "https://cdn.example.com/photos/abc.jpg",
          "notes": "Caught on a fly"
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DownloadResponse.self, from: json)
    XCTAssertEqual(response.catch_reports.count, 1)

    let report = response.catch_reports[0]
    XCTAssertEqual(report.catch_id, "abc-123")
    XCTAssertEqual(report.id, "abc-123", "id convenience property should match catch_id")
    XCTAssertEqual(report.river, "Skeena")
    XCTAssertEqual(report.latitude ?? 0, 54.123, accuracy: 0.001)
    XCTAssertEqual(report.longitude ?? 0, -128.456, accuracy: 0.001)
    XCTAssertEqual(report.notes, "Caught on a fly")
    XCTAssertNotNil(report.photoURL, "photoURL should parse valid URL string")
    XCTAssertEqual(report.photoURL?.absoluteString, "https://cdn.example.com/photos/abc.jpg")
  }

  func testDownloadResponseDecoding_nullOptionals() throws {
    let json = """
    {
      "catch_reports": [
        {
          "catch_id": "xyz-789",
          "created_at": "2026-03-01T00:00:00Z",
          "river": "Copper",
          "latitude": null,
          "longitude": null,
          "photo_url": null,
          "notes": null
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DownloadResponse.self, from: json)
    let report = response.catch_reports[0]

    XCTAssertNil(report.latitude, "latitude should be nil when null in JSON")
    XCTAssertNil(report.longitude, "longitude should be nil when null in JSON")
    XCTAssertNil(report.photo_url, "photo_url should be nil when null in JSON")
    XCTAssertNil(report.photoURL, "photoURL should be nil when photo_url is null")
    XCTAssertNil(report.notes, "notes should be nil when null in JSON")
  }

  func testDownloadResponseDecoding_emptyReports() throws {
    let json = """
    {"catch_reports": []}
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DownloadResponse.self, from: json)
    XCTAssertTrue(response.catch_reports.isEmpty, "Should decode empty catch_reports array")
  }

  // MARK: - Routing Logic

  /// Replicates the app's routing logic: user type determines which landing view to show.
  private func landingViewName(for userType: AuthService.UserType?) -> String {
    guard let t = userType else { return "LoginView" }
    switch t {
    case .guide: return "LandingView"
    case .angler: return "AnglerLandingView"
    }
  }

  func testRouting_anglerType_routesToAnglerLandingView() {
    XCTAssertEqual(landingViewName(for: .angler), "AnglerLandingView",
                   "Angler user type should route to AnglerLandingView")
  }

  func testRouting_guideType_routesToLandingView() {
    XCTAssertEqual(landingViewName(for: .guide), "LandingView",
                   "Guide user type should route to LandingView")
  }

  func testRouting_nilType_routesToLoginView() {
    XCTAssertEqual(landingViewName(for: nil), "LoginView",
                   "Nil user type should route to LoginView")
  }

  // MARK: - Keychain helpers

  @discardableResult
  private func setKeychain(account: String, value: String) -> Bool {
    let delQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account
    ]
    SecItemDelete(delQuery as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    let addQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account,
      kSecValueData: data
    ]
    return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
  }
}
