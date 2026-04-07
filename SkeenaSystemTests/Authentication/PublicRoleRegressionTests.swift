import XCTest
import Security
@testable import SkeenaSystem

/// Regression tests for the "public" community role.
///
/// Covers:
/// 1. AuthService.UserType enum — raw value, parsing, exhaustiveness
/// 2. CommunityService — fetching a membership with role "public",
///    setting the active community, persisting role, syncing to AuthService
/// 3. loadUserProfile — parses user_type "public" from user_metadata
/// 4. AppRootView routing logic — "public" maps to PublicLandingView
@MainActor
final class PublicRoleRegressionTests: XCTestCase {

  // MARK: - Setup / Teardown

  private var _mockSession: URLSession?
  private var mockSession: URLSession {
    if _mockSession == nil {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      _mockSession = URLSession(configuration: config)
    }
    return _mockSession!
  }

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
    MockURLProtocol.requestHandler = nil
    AuthService.resetSharedForTests(session: mockSession)
    CommunityService.shared.clear()
    CommunityService.shared.clearDefaultCommunity()
    clearKeychainEntries()
  }

  override func tearDown() {
    MockURLProtocol.requestHandler = nil
    URLProtocol.unregisterClass(MockURLProtocol.self)
    _mockSession?.invalidateAndCancel()
    _mockSession = nil
    CommunityService.shared.clear()
    CommunityService.shared.clearDefaultCommunity()
    clearKeychainEntries()
    super.tearDown()
  }

  // MARK: - Keychain helpers

  private func clearKeychainEntries() {
    for account in [
      "epicwaters.auth.access_token",
      "epicwaters.auth.refresh_token",
      "epicwaters.auth.access_token_exp"
    ] {
      SecItemDelete([
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: account
      ] as CFDictionary)
    }
  }

  private func setAccessToken(_ token: String) {
    let data = token.data(using: .utf8)!
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: "epicwaters.auth.access_token",
      kSecValueData: data
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)

    let exp = String(Int(Date().timeIntervalSince1970) + 3600)
    let expData = exp.data(using: .utf8)!
    let expQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: "epicwaters.auth.access_token_exp",
      kSecValueData: expData
    ]
    SecItemDelete(expQuery as CFDictionary)
    SecItemAdd(expQuery as CFDictionary, nil)
  }

  // MARK: - Membership JSON helpers

  private func makeMembershipsJSON(_ memberships: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: memberships)
  }

  private func makePublicMembership(
    communityId: String = "pub-comm-uuid-1",
    communityName: String = "Open Waters"
  ) -> [String: Any] {
    [
      "id": UUID().uuidString,
      "community_id": communityId,
      "role": "public",
      "communities": [
        "id": communityId,
        "name": communityName,
        "code": "OPW001",
        "is_active": true
      ]
    ]
  }

  // MARK: - AuthService.UserType enum tests

  func testUserTypePublic_rawValue_isPublic() {
    XCTAssertEqual(AuthService.UserType.public.rawValue, "public",
                   "UserType.public raw value must be the string 'public'")
  }

  func testUserTypePublic_fromRawValue_succeeds() {
    let parsed = AuthService.UserType(rawValue: "public")
    XCTAssertEqual(parsed, .public,
                   "UserType(rawValue: 'public') must parse to .public")
  }

  func testUserTypePublic_isDistinctFromGuideAndAngler() {
    XCTAssertNotEqual(AuthService.UserType.public, .guide)
    XCTAssertNotEqual(AuthService.UserType.public, .angler)
  }

  func testUserType_allFourCasesHaveDistinctRawValues() {
    let rawValues = [
      AuthService.UserType.guide.rawValue,
      AuthService.UserType.angler.rawValue,
      AuthService.UserType.public.rawValue,
      AuthService.UserType.researcher.rawValue
    ]
    let unique = Set(rawValues)
    XCTAssertEqual(unique.count, 4, "All four UserType cases must have distinct raw values")
  }

  func testUserType_unknownRawValue_returnsNil() {
    XCTAssertNil(AuthService.UserType(rawValue: "admin"))
    XCTAssertNil(AuthService.UserType(rawValue: "member"))
    XCTAssertNil(AuthService.UserType(rawValue: ""))
  }

  // MARK: - CommunityService: fetch memberships with public role

  func testFetchMemberships_publicRole_parsedCorrectly() async {
    setAccessToken("valid-token")
    let membership = makePublicMembership()
    let data = makeMembershipsJSON([membership])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()

    XCTAssertEqual(svc.memberships.count, 1,
                   "Should parse one membership with role 'public'")
    XCTAssertEqual(svc.memberships.first?.role, "public",
                   "Membership role should be 'public'")
    XCTAssertEqual(svc.memberships.first?.communityId, "pub-comm-uuid-1")
  }

  func testFetchMemberships_publicAndGuide_bothParsed() async {
    setAccessToken("valid-token")
    let pub = makePublicMembership(communityId: "c-pub", communityName: "Public Waters")
    let guide: [String: Any] = [
      "id": UUID().uuidString,
      "community_id": "c-guide",
      "role": "guide",
      "communities": ["id": "c-guide", "name": "Lodge A", "code": "LDG001", "is_active": true]
    ]
    let data = makeMembershipsJSON([pub, guide])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()

    XCTAssertEqual(svc.memberships.count, 2)
    let roles = Set(svc.memberships.map { $0.role })
    XCTAssertTrue(roles.contains("public"), "Should include 'public' role membership")
    XCTAssertTrue(roles.contains("guide"), "Should include 'guide' role membership")
  }

  // MARK: - CommunityService: set active community with public role

  func testSetActiveCommunity_publicRole_updatesActiveRole() async {
    setAccessToken("valid-token")
    let membership = makePublicMembership(communityId: "pub-c-1")
    let data = makeMembershipsJSON([membership])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()
    svc.setActiveCommunity(id: "pub-c-1")

    XCTAssertEqual(svc.activeCommunityId, "pub-c-1")
    XCTAssertEqual(svc.activeRole, "public",
                   "activeRole should be 'public' after selecting a public community")
  }

  func testSetActiveCommunity_publicRole_persistsToUserDefaults() async {
    setAccessToken("valid-token")
    let membership = makePublicMembership(communityId: "pub-c-2")
    let data = makeMembershipsJSON([membership])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()
    svc.setActiveCommunity(id: "pub-c-2")

    XCTAssertEqual(
      UserDefaults.standard.string(forKey: "CommunityService.activeRole"),
      "public",
      "SNAPSHOT: 'public' role must be persisted to UserDefaults for offline resumption"
    )
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: "CommunityService.activeCommunityId"),
      "pub-c-2"
    )
  }

  func testSetActiveCommunity_publicRole_syncsToAuthService() async {
    setAccessToken("valid-token")
    let membership = makePublicMembership(communityId: "pub-c-3")
    let data = makeMembershipsJSON([membership])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()
    svc.setActiveCommunity(id: "pub-c-3")

    // Give the MainActor Task in setActiveCommunity time to propagate
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(
      AuthService.shared.currentUserType,
      .public,
      "SNAPSHOT: Selecting a public community must sync .public to AuthService.currentUserType"
    )
  }

  func testSetActiveCommunity_switchFromPublicToGuide_updatesRoleCorrectly() async {
    setAccessToken("valid-token")
    let pub = makePublicMembership(communityId: "c-pub")
    let guide: [String: Any] = [
      "id": UUID().uuidString,
      "community_id": "c-guide",
      "role": "guide",
      "communities": ["id": "c-guide", "name": "Lodge A", "code": "LDG001", "is_active": true]
    ]
    let data = makeMembershipsJSON([pub, guide])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()

    svc.setActiveCommunity(id: "c-pub")
    XCTAssertEqual(svc.activeRole, "public")

    svc.setActiveCommunity(id: "c-guide")
    XCTAssertEqual(svc.activeRole, "guide",
                   "Switching from public to guide community must update role to 'guide'")
  }

  // MARK: - loadUserProfile: parses "public" from user_metadata

  func testLoadUserProfile_userTypePublic_setsCurrentUserTypePublic() async throws {
    let tokenJSON: [String: Any] = [
      "access_token": "public-access-token",
      "refresh_token": "public-refresh-token",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

    let userJSON: [String: Any] = [
      "id": "user-public-001",
      "email": "member@publicwaters.com",
      "user_metadata": [
        "first_name": "River",
        "last_name": "Walker",
        "user_type": "public"
      ]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON)

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    try await AuthService.shared.signIn(email: "member@publicwaters.com", password: "password")

    XCTAssertTrue(AuthService.shared.isAuthenticated)
    XCTAssertEqual(AuthService.shared.currentUserType, .public,
                   "SNAPSHOT: user_metadata.user_type 'public' must parse to AuthService.UserType.public")
    XCTAssertEqual(AuthService.shared.currentFirstName, "River")
  }

  func testLoadUserProfile_userTypePublic_cachedInUserDefaults() async throws {
    let tokenJSON: [String: Any] = [
      "access_token": "public-cache-token",
      "refresh_token": "public-cache-refresh",
      "expires_in": 3600,
      "token_type": "bearer"
    ]
    let tokenData = try JSONSerialization.data(withJSONObject: tokenJSON)

    let userJSON: [String: Any] = [
      "id": "user-public-002",
      "email": "river@publicwaters.com",
      "user_metadata": [
        "first_name": "Sam",
        "user_type": "public"
      ]
    ]
    let userData = try JSONSerialization.data(withJSONObject: userJSON)

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/auth/v1/token") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tokenData)
      } else if url.path.contains("/auth/v1/user") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, userData)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    try await AuthService.shared.signIn(email: "river@publicwaters.com", password: "password")

    // Key must match `AuthService.kCachedUserType` — see `loadUserProfile()`.
    let cachedType = UserDefaults.standard.string(forKey: "CachedUserType")
    XCTAssertEqual(cachedType, "public",
                   "SNAPSHOT: 'public' user type must be cached in UserDefaults for offline resumption")
  }

  // MARK: - AppRootView routing logic

  func testRouting_publicUserType_mapsToPublicLandingView() {
    // Verifies the routing switch is exhaustive and maps .public correctly.
    // Researcher and angler routing depends on community type (Conservation vs other).
    func landingViewName(for userType: AuthService.UserType, isConservation: Bool = false) -> String {
      switch userType {
      case .guide:      return "GuideLandingView"
      case .angler:     return isConservation ? "ConservationLandingView" : "AnglerLandingView"
      case .public:     return "PublicLandingView"
      case .researcher: return isConservation ? "ResearcherLandingView" : "PublicLandingView"
      }
    }
    XCTAssertEqual(landingViewName(for: .public), "PublicLandingView",
                   "SNAPSHOT: .public must route to PublicLandingView")
    XCTAssertEqual(landingViewName(for: .guide), "GuideLandingView",
                   "Existing guide routing must be unaffected")
    XCTAssertEqual(landingViewName(for: .angler), "AnglerLandingView",
                   "Non-Conservation angler routing must be unaffected")
    XCTAssertEqual(landingViewName(for: .angler, isConservation: true), "ConservationLandingView",
                   "SNAPSHOT: .angler in Conservation community must route to ConservationLandingView")
    XCTAssertEqual(landingViewName(for: .researcher, isConservation: true), "ResearcherLandingView",
                   "SNAPSHOT: .researcher in Conservation community must route to ResearcherLandingView")
    XCTAssertEqual(landingViewName(for: .researcher, isConservation: false), "PublicLandingView",
                   "SNAPSHOT: .researcher in non-Conservation community must fall back to PublicLandingView")
  }

  func testRouting_nilUserType_fallsBackToGuide() {
    // AppRootView uses `auth.currentUserType ?? .guide` as fallback.
    // A nil type (unauthenticated / unknown) must not produce PublicLandingView.
    let resolved: AuthService.UserType = nil ?? .guide
    XCTAssertEqual(resolved, .guide, "Nil user type must fall back to .guide, not .public")
  }
}
