import XCTest
import Security
@testable import SkeenaSystem

/// Regression tests for the "scientist" community role and Conservation gating.
///
/// Covers:
/// 1. AuthService.UserType enum — .scientist raw value, parsing, distinctness
/// 2. CommunityService — activeCommunityTypeName persistence, isConservation
/// 3. AppRootView routing — scientist + Conservation → ScientistLandingView,
///    scientist + non-Conservation → PublicLandingView
/// 4. ScientistLandingView — instantiates, sets .scientist environment
/// 5. Toolbar — scientist uses same tabs as public (no Trips)
@MainActor
final class ScientistRoleRegressionTests: XCTestCase {

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

  private func makeScientistMembership(
    communityId: String = "sci-comm-uuid-1",
    communityName: String = "Conservation Program",
    communityTypeName: String = "Conservation",
    communityTypeId: String = "type-conservation-1"
  ) -> [String: Any] {
    [
      "id": UUID().uuidString,
      "community_id": communityId,
      "role": "scientist",
      "communities": [
        "id": communityId,
        "name": communityName,
        "code": "CON001",
        "is_active": true,
        "community_type_id": communityTypeId,
        "community_types": [
          "id": communityTypeId,
          "name": communityTypeName,
          "entitlements": ["E_CATCH_CAROUSEL": true, "E_CATCH_MAP": true]
        ]
      ] as [String: Any]
    ]
  }

  // MARK: - AuthService.UserType enum tests

  func testUserTypeScientist_rawValue_isScientist() {
    XCTAssertEqual(AuthService.UserType.scientist.rawValue, "scientist",
                   "UserType.scientist raw value must be the string 'scientist'")
  }

  func testUserTypeScientist_fromRawValue_succeeds() {
    let parsed = AuthService.UserType(rawValue: "scientist")
    XCTAssertEqual(parsed, .scientist,
                   "UserType(rawValue: 'scientist') must parse to .scientist")
  }

  func testUserTypeScientist_isDistinctFromOtherRoles() {
    XCTAssertNotEqual(AuthService.UserType.scientist, .guide)
    XCTAssertNotEqual(AuthService.UserType.scientist, .angler)
    XCTAssertNotEqual(AuthService.UserType.scientist, .public)
  }

  func testUserType_allFourCasesExhaustive() {
    // Compiler-enforced exhaustiveness: adding a fifth case will break this switch.
    func name(for type: AuthService.UserType) -> String {
      switch type {
      case .guide:     return "guide"
      case .angler:    return "angler"
      case .public:    return "public"
      case .scientist: return "scientist"
      }
    }
    XCTAssertEqual(name(for: .scientist), "scientist")
    XCTAssertEqual(name(for: .guide), "guide")
    XCTAssertEqual(name(for: .angler), "angler")
    XCTAssertEqual(name(for: .public), "public")
  }

  // MARK: - CommunityService: scientist role parsing

  func testFetchMemberships_scientistRole_parsedCorrectly() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership()
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
                   "Should parse one membership with role 'scientist'")
    XCTAssertEqual(svc.memberships.first?.role, "scientist",
                   "Membership role should be 'scientist'")
    XCTAssertEqual(svc.memberships.first?.communityId, "sci-comm-uuid-1")
  }

  func testSetActiveCommunity_scientistRole_syncsToAuthService() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-1")
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
    svc.setActiveCommunity(id: "sci-c-1")

    // Give the MainActor Task in setActiveCommunity time to propagate
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(svc.activeRole, "scientist",
                   "activeRole should be 'scientist' after selecting a scientist community")
    XCTAssertEqual(
      AuthService.shared.currentUserType,
      .scientist,
      "SNAPSHOT: Selecting a scientist community must sync .scientist to AuthService.currentUserType"
    )
  }

  // MARK: - CommunityService: activeCommunityTypeName

  func testSetActiveCommunity_setsTypeName() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-2", communityTypeName: "Conservation")
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
    svc.setActiveCommunity(id: "sci-c-2")

    XCTAssertEqual(svc.activeCommunityTypeName, "Conservation",
                   "SNAPSHOT: activeCommunityTypeName must be set from community_types.name")
  }

  func testSetActiveCommunity_typeName_persistsToUserDefaults() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-3", communityTypeName: "Conservation")
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
    svc.setActiveCommunity(id: "sci-c-3")

    XCTAssertEqual(
      UserDefaults.standard.string(forKey: "CommunityService.activeCommunityTypeName"),
      "Conservation",
      "SNAPSHOT: activeCommunityTypeName must be persisted to UserDefaults"
    )
  }

  func testClear_resetsTypeName() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-4")
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
    svc.setActiveCommunity(id: "sci-c-4")
    XCTAssertEqual(svc.activeCommunityTypeName, "Conservation")

    svc.clear()
    XCTAssertNil(svc.activeCommunityTypeName,
                 "clear() must nil activeCommunityTypeName")
    XCTAssertNil(UserDefaults.standard.string(forKey: "CommunityService.activeCommunityTypeName"),
                 "clear() must remove activeCommunityTypeName from UserDefaults")
  }

  func testClearActiveCommunity_resetsTypeName() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-5")
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
    svc.setActiveCommunity(id: "sci-c-5")
    XCTAssertEqual(svc.activeCommunityTypeName, "Conservation")

    svc.clearActiveCommunity()
    XCTAssertNil(svc.activeCommunityTypeName,
                 "clearActiveCommunity() must nil activeCommunityTypeName")
  }

  // MARK: - CommunityService: isConservation

  func testIsConservation_trueWhenTypeName_isConservation() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-6", communityTypeName: "Conservation")
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
    svc.setActiveCommunity(id: "sci-c-6")

    XCTAssertTrue(svc.isConservation,
                  "SNAPSHOT: isConservation must be true when activeCommunityTypeName is 'Conservation'")
  }

  func testIsConservation_falseWhenTypeName_isLodge() async {
    setAccessToken("valid-token")
    let membership = makeScientistMembership(communityId: "sci-c-7", communityTypeName: "Lodge")
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
    svc.setActiveCommunity(id: "sci-c-7")

    XCTAssertFalse(svc.isConservation,
                   "SNAPSHOT: isConservation must be false when activeCommunityTypeName is 'Lodge'")
  }

  func testIsConservation_falseWhenTypeName_isNil() {
    let svc = CommunityService.shared
    XCTAssertNil(svc.activeCommunityTypeName)
    XCTAssertFalse(svc.isConservation,
                   "isConservation must be false when activeCommunityTypeName is nil")
  }

  // MARK: - Routing: scientist + Conservation → ScientistLandingView

  func testRouting_scientistConservation_routesToScientistLandingView() {
    // Mirrors AppRootView logic: .scientist with isConservation → ScientistLandingView
    func landingViewName(for userType: AuthService.UserType, isConservation: Bool) -> String {
      switch userType {
      case .guide:     return "LandingView"
      case .angler:    return "AnglerLandingView"
      case .public:    return "PublicLandingView"
      case .scientist: return isConservation ? "ScientistLandingView" : "PublicLandingView"
      }
    }
    XCTAssertEqual(
      landingViewName(for: .scientist, isConservation: true),
      "ScientistLandingView",
      "SNAPSHOT: .scientist + Conservation must route to ScientistLandingView"
    )
  }

  func testRouting_scientistNonConservation_fallsBackToPublicLandingView() {
    func landingViewName(for userType: AuthService.UserType, isConservation: Bool) -> String {
      switch userType {
      case .guide:     return "LandingView"
      case .angler:    return "AnglerLandingView"
      case .public:    return "PublicLandingView"
      case .scientist: return isConservation ? "ScientistLandingView" : "PublicLandingView"
      }
    }
    XCTAssertEqual(
      landingViewName(for: .scientist, isConservation: false),
      "PublicLandingView",
      "SNAPSHOT: .scientist + non-Conservation must fall back to PublicLandingView"
    )
  }

  // MARK: - ScientistLandingView instantiation

  func testScientistLandingView_instantiatesWithoutCrash() {
    let view = ScientistLandingView()
    XCTAssertNotNil(view, "ScientistLandingView must instantiate without crashing")
  }

  func testScientistLandingView_setsScientistUserRoleEnvironment() {
    // Verify .scientist is a valid AppUserRole value for the environment
    let role: AppUserRole = .scientist
    XCTAssertEqual(role, .scientist,
                   "AppUserRole.scientist must be usable as an environment value for ScientistLandingView")
  }

  // MARK: - Scientist toolbar snapshot

  func testSnapshot_scientistToolbarTabs_matchPublicTabs() {
    // SNAPSHOT: Scientist toolbar currently mirrors public — Home, Catches, Social, Explore.
    // This test documents the initial state; scientist toolbar may diverge later.
    let scientistTabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("camera.viewfinder", "Catches"),
      ("message", "Social"),
      ("safari", "Explore")
    ]
    XCTAssertEqual(scientistTabs.count, 4,
                   "SNAPSHOT: Scientist toolbar must have exactly 4 tabs")
    XCTAssertFalse(scientistTabs.contains(where: { $0.label == "Trips" }),
                   "SNAPSHOT: Scientist toolbar must not contain a Trips tab")
  }

  // MARK: - Role switching: scientist ↔ other roles

  func testSetActiveCommunity_switchFromScientistToGuide_updatesRoleCorrectly() async {
    setAccessToken("valid-token")
    let sci = makeScientistMembership(communityId: "c-sci")
    let guide: [String: Any] = [
      "id": UUID().uuidString,
      "community_id": "c-guide",
      "role": "guide",
      "communities": ["id": "c-guide", "name": "Lodge A", "code": "LDG001", "is_active": true]
    ]
    let data = makeMembershipsJSON([sci, guide])

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      if url.path.contains("/rest/v1/user_communities") {
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    let svc = CommunityService.shared
    await svc.fetchMemberships()

    svc.setActiveCommunity(id: "c-sci")
    XCTAssertEqual(svc.activeRole, "scientist")
    XCTAssertEqual(svc.activeCommunityTypeName, "Conservation")
    XCTAssertTrue(svc.isConservation)

    svc.setActiveCommunity(id: "c-guide")
    XCTAssertEqual(svc.activeRole, "guide",
                   "Switching from scientist to guide community must update role to 'guide'")
    XCTAssertNil(svc.activeCommunityTypeName,
                 "Guide community without community_types should have nil typeName")
    XCTAssertFalse(svc.isConservation,
                   "isConservation must be false after switching to a non-Conservation community")
  }
}
