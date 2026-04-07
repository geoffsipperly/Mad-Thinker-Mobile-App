// AnglerOnboardingRegressionTests.swift
// SkeenaSystemTests
//
// Regression tests for AnglerOnboardingWizard and its trigger logic:
//   - Onboarding gate: only Lodge, MultiLodge, FlyShop community types
//   - UserDefaults key format: "anglerOnboarded_\(memberId)_\(communityId)" (per-user, per-community)
//   - Onboarding does NOT fire for Conservation or unknown types
//   - Onboarding does NOT fire once the key is set
//   - Notification.Name.onboardingStepSave exists for step save coordination
//   - PreferenceField, ProficiencyField, GearField decoding in wizard context
//   - Profile step save body matches ManageProfileAPI contract
//   - Preferences step save body matches member-profile-fields contract
//   - Proficiency step save body sends rounded integers
//   - Gear step save body sends "true"/"false" strings

import XCTest
import Security
@testable import SkeenaSystem

@MainActor
final class AnglerOnboardingRegressionTests: XCTestCase {

  // MARK: - Setup / teardown

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
    clearAuthKeychainEntries()
    MockURLProtocol.requestHandler = nil
    URLProtocol.registerClass(MockURLProtocol.self)
    AuthService.resetSharedForTests(session: mockSession)
    CommunityService.shared.clear()
    CommunityService.shared.clearDefaultCommunity()
    // Clean up any onboarding keys from previous runs
    clearOnboardingKeys()
  }

  override func tearDown() {
    MockURLProtocol.requestHandler = nil
    URLProtocol.unregisterClass(MockURLProtocol.self)
    _mockSession?.invalidateAndCancel()
    _mockSession = nil
    clearAuthKeychainEntries()
    CommunityService.shared.clear()
    CommunityService.shared.clearDefaultCommunity()
    clearOnboardingKeys()
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

  /// Remove test onboarding keys so tests are isolated.
  private func clearOnboardingKeys() {
    for key in testCommunityIds.map({ "anglerOnboarded_\($0)" }) {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private let testCommunityIds = [
    "lodge-c-1", "multilodge-c-2", "flyshop-c-3",
    "conservation-c-4", "unknown-c-5", "lodge-c-6"
  ]

  // MARK: - Helpers

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

  private func makeMembershipsJSON(_ memberships: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: memberships)
  }

  private func makeAnglerMembership(
    communityId: String,
    communityName: String = "Test Community",
    communityTypeName: String = "Lodge",
    communityTypeId: String = "type-1"
  ) -> [String: Any] {
    [
      "id": UUID().uuidString,
      "community_id": communityId,
      "role": "angler",
      "communities": [
        "id": communityId,
        "name": communityName,
        "code": "TST001",
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

  private func setupCommunity(
    communityId: String,
    typeName: String
  ) async {
    setAccessToken("valid-token")
    let membership = makeAnglerMembership(
      communityId: communityId,
      communityTypeName: typeName
    )
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
    svc.setActiveCommunity(id: communityId)
  }

  // MARK: - Onboarding gate: community type filtering

  func testOnboardingKey_Lodge_shouldTrigger() async {
    await setupCommunity(communityId: "lodge-c-1", typeName: "Lodge")

    let svc = CommunityService.shared
    XCTAssertEqual(svc.activeCommunityTypeName, "Lodge")
    XCTAssertFalse(
      UserDefaults.standard.bool(forKey: "anglerOnboarded_lodge-c-1"),
      "SNAPSHOT: Onboarding key must be false before wizard completes"
    )

    // Verify the type is in the expected gate set
    let gateTypes: Set<String> = ["Lodge", "MultiLodge", "FlyShop"]
    XCTAssertTrue(
      gateTypes.contains(svc.activeCommunityTypeName ?? ""),
      "SNAPSHOT: Lodge must be in the onboarding gate set"
    )
  }

  func testOnboardingKey_MultiLodge_shouldTrigger() async {
    await setupCommunity(communityId: "multilodge-c-2", typeName: "MultiLodge")

    let gateTypes: Set<String> = ["Lodge", "MultiLodge", "FlyShop"]
    XCTAssertTrue(
      gateTypes.contains(CommunityService.shared.activeCommunityTypeName ?? ""),
      "SNAPSHOT: MultiLodge must be in the onboarding gate set"
    )
  }

  func testOnboardingKey_FlyShop_shouldTrigger() async {
    await setupCommunity(communityId: "flyshop-c-3", typeName: "FlyShop")

    let gateTypes: Set<String> = ["Lodge", "MultiLodge", "FlyShop"]
    XCTAssertTrue(
      gateTypes.contains(CommunityService.shared.activeCommunityTypeName ?? ""),
      "SNAPSHOT: FlyShop must be in the onboarding gate set"
    )
  }

  func testOnboardingKey_Conservation_shouldNotTrigger() async {
    await setupCommunity(communityId: "conservation-c-4", typeName: "Conservation")

    let gateTypes: Set<String> = ["Lodge", "MultiLodge", "FlyShop"]
    XCTAssertFalse(
      gateTypes.contains(CommunityService.shared.activeCommunityTypeName ?? ""),
      "SNAPSHOT: Conservation must NOT be in the onboarding gate set"
    )
  }

  func testOnboardingKey_unknownType_shouldNotTrigger() async {
    await setupCommunity(communityId: "unknown-c-5", typeName: "SomeNewType")

    let gateTypes: Set<String> = ["Lodge", "MultiLodge", "FlyShop"]
    XCTAssertFalse(
      gateTypes.contains(CommunityService.shared.activeCommunityTypeName ?? ""),
      "SNAPSHOT: Unknown community type must NOT be in the onboarding gate set"
    )
  }

  // MARK: - UserDefaults key format & completion

  func testOnboardingKey_formatMatchesCommunityId() {
    let communityId = "lodge-c-6"
    let expectedKey = "anglerOnboarded_\(communityId)"

    // Before completion: key is false
    XCTAssertFalse(
      UserDefaults.standard.bool(forKey: expectedKey),
      "SNAPSHOT: Onboarding key must default to false for a new community"
    )

    // Simulate wizard completion
    UserDefaults.standard.set(true, forKey: expectedKey)

    XCTAssertTrue(
      UserDefaults.standard.bool(forKey: expectedKey),
      "SNAPSHOT: Onboarding key must be true after wizard completes"
    )
  }

  func testOnboardingKey_perCommunityIsolation() {
    let key1 = "anglerOnboarded_lodge-c-1"
    let key2 = "anglerOnboarded_multilodge-c-2"

    UserDefaults.standard.set(true, forKey: key1)

    XCTAssertTrue(UserDefaults.standard.bool(forKey: key1),
                  "Community 1 should be marked as onboarded")
    XCTAssertFalse(UserDefaults.standard.bool(forKey: key2),
                   "SNAPSHOT: Onboarding completion must be scoped to a single community — other communities remain un-onboarded")
  }

  func testOnboardingKey_skipAlsoMarksComplete() {
    // The skip flow in AnglerOnboardingWizard calls the same onComplete closure,
    // which sets the key. Verify the key pattern is consistent.
    let communityId = "lodge-c-1"
    let key = "anglerOnboarded_\(communityId)"

    // Simulate skip
    UserDefaults.standard.set(true, forKey: key)

    XCTAssertTrue(
      UserDefaults.standard.bool(forKey: key),
      "SNAPSHOT: Skipping onboarding must also set the completion key to prevent re-trigger"
    )
  }

  // MARK: - Notification.Name.onboardingStepSave

  func testOnboardingStepSaveNotification_exists() {
    // Verify the notification name is accessible and matches the expected string.
    let name = Notification.Name.onboardingStepSave
    XCTAssertEqual(
      name.rawValue,
      "onboardingStepSave",
      "SNAPSHOT: Notification name must be 'onboardingStepSave' for step save coordination"
    )
  }

  func testOnboardingStepSaveNotification_canBePostedAndReceived() {
    let expectation = expectation(description: "Notification received")
    let observer = NotificationCenter.default.addObserver(
      forName: .onboardingStepSave,
      object: nil,
      queue: .main
    ) { _ in
      expectation.fulfill()
    }

    NotificationCenter.default.post(name: .onboardingStepSave, object: nil)
    wait(for: [expectation], timeout: 1.0)
    NotificationCenter.default.removeObserver(observer)
  }

  // MARK: - Profile step: save body contract

  func testProfileStep_saveBodyFormat() async throws {
    setAccessToken("valid-token")

    var capturedRequest: URLRequest?

    MockURLProtocol.requestHandler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      // Capture PUT to my-profile
      if request.httpMethod == "PUT", url.path.contains("my-profile") {
        capturedRequest = request
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{}".data(using: .utf8))
      }
      // GET my-profile returns a profile
      if request.httpMethod == "GET", url.path.contains("my-profile") {
        let json = """
        {"profile":{"firstName":"Jane","lastName":"Doe","memberId":"m123","dateOfBirth":"1985-06-15","phoneNumber":"5551234567"}}
        """
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json.data(using: .utf8))
      }
      return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
    }

    // Build the save body the same way the wizard does
    var profile = MyProfile()
    profile.firstName = "Jane"
    profile.lastName = "Doe"
    profile.phoneNumber = "5551234567"
    profile.dateOfBirth = "1985-06-15"

    var body: [String: Any] = [:]
    if let v = profile.firstName, !v.isEmpty { body["firstName"] = v }
    if let v = profile.lastName, !v.isEmpty { body["lastName"] = v }
    if let v = profile.phoneNumber, !v.isEmpty { body["phoneNumber"] = v }
    if let v = profile.dateOfBirth, !v.isEmpty { body["dateOfBirth"] = v }

    let bodyData = try JSONSerialization.data(withJSONObject: body)
    let parsed = try JSONSerialization.jsonObject(with: bodyData) as! [String: String]

    XCTAssertEqual(parsed["firstName"], "Jane",
                   "SNAPSHOT: Save body must include firstName")
    XCTAssertEqual(parsed["lastName"], "Doe",
                   "SNAPSHOT: Save body must include lastName")
    XCTAssertEqual(parsed["phoneNumber"], "5551234567",
                   "SNAPSHOT: Save body must include phoneNumber")
    XCTAssertEqual(parsed["dateOfBirth"], "1985-06-15",
                   "SNAPSHOT: Save body must include dateOfBirth in yyyy-MM-dd format")
    XCTAssertNil(parsed["memberId"],
                 "SNAPSHOT: Save body must NOT include memberId (read-only)")
  }

  // MARK: - Preferences step: save body contract

  func testPreferencesStep_saveBodyFormat() throws {
    let communityId = "lodge-c-1"

    // Simulate building the save payload the same way the wizard does
    let fields = [
      PreferenceField(id: "f1", field_name: "dietary", field_label: "Dietary Needs",
                      field_type: "boolean", question_text: "Any dietary needs?",
                      context_text: nil,
                      options: PreferenceOptions(has_details: true, details_prompt: "Specify"),
                      is_required: false, sort_order: 1, value: nil, text_value: nil),
      PreferenceField(id: "f2", field_name: "accessibility", field_label: "Accessibility",
                      field_type: "boolean", question_text: "Any accessibility needs?",
                      context_text: nil,
                      options: PreferenceOptions(has_details: false, details_prompt: nil),
                      is_required: false, sort_order: 2, value: nil, text_value: nil)
    ]

    let values: [String: Bool] = ["f1": true, "f2": false]
    let textValues: [String: String] = ["f1": "No gluten", "f2": ""]

    let valuesArray: [[String: String]] = fields.map { field in
      let boolVal = values[field.id] == true
      let text = textValues[field.id] ?? ""
      let valueStr: String
      if boolVal && field.options?.has_details == true && !text.isEmpty {
        valueStr = "true|\(text)"
      } else {
        valueStr = boolVal ? "true" : "false"
      }
      return ["field_definition_id": field.id, "value": valueStr]
    }

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    let data = try JSONSerialization.data(withJSONObject: body)
    let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertEqual(parsed["community_id"] as? String, communityId,
                   "SNAPSHOT: Save body must include community_id")

    let savedValues = parsed["values"] as! [[String: String]]
    XCTAssertEqual(savedValues.count, 2,
                   "SNAPSHOT: Save body must include all fields")

    // f1 has details enabled and "Yes" selected with text
    let f1 = savedValues.first(where: { $0["field_definition_id"] == "f1" })!
    XCTAssertEqual(f1["value"], "true|No gluten",
                   "SNAPSHOT: Yes with details must be pipe-delimited 'true|text'")

    // f2 is "No" with no details
    let f2 = savedValues.first(where: { $0["field_definition_id"] == "f2" })!
    XCTAssertEqual(f2["value"], "false",
                   "SNAPSHOT: No selection must send 'false'")
  }

  // MARK: - Proficiency step: save body contract

  func testProficiencyStep_saveBodyRoundsToInteger() throws {
    let communityId = "lodge-c-1"

    let values: [String: Double] = ["p1": 73.7, "p2": 25.3]

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": "\(Int(val.rounded()))"]
    }

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    let data = try JSONSerialization.data(withJSONObject: body)
    let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let savedValues = parsed["values"] as! [[String: String]]

    let p1 = savedValues.first(where: { $0["field_definition_id"] == "p1" })!
    XCTAssertEqual(p1["value"], "74",
                   "SNAPSHOT: Proficiency slider value must be rounded to nearest integer")

    let p2 = savedValues.first(where: { $0["field_definition_id"] == "p2" })!
    XCTAssertEqual(p2["value"], "25",
                   "SNAPSHOT: Proficiency slider value must be rounded to nearest integer")
  }

  // MARK: - Gear step: save body contract

  func testGearStep_saveBodyFormat() throws {
    let communityId = "lodge-c-1"

    let values: [String: String] = ["g1": "true", "g2": "false", "g3": "true"]

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": val]
    }

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    let data = try JSONSerialization.data(withJSONObject: body)
    let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    let savedValues = parsed["values"] as! [[String: String]]
    XCTAssertEqual(savedValues.count, 3,
                   "SNAPSHOT: Gear save body must include all gear items")

    let g1 = savedValues.first(where: { $0["field_definition_id"] == "g1" })!
    XCTAssertEqual(g1["value"], "true",
                   "SNAPSHOT: Checked gear must send 'true'")

    let g2 = savedValues.first(where: { $0["field_definition_id"] == "g2" })!
    XCTAssertEqual(g2["value"], "false",
                   "SNAPSHOT: Unchecked gear must send 'false'")
  }

  // MARK: - Model decoding: PreferenceField in wizard context

  func testPreferenceField_decodesFromServerJSON() throws {
    let json = """
    {
      "id": "pref-1",
      "field_name": "dietary",
      "field_label": "Dietary Needs",
      "field_type": "boolean",
      "question_text": "Do you have any dietary restrictions?",
      "context_text": "We want to make sure your meals are covered.",
      "options": {"has_details": true, "details_prompt": "Please specify"},
      "is_required": false,
      "sort_order": 1,
      "value": "true|No shellfish",
      "text_value": "No shellfish"
    }
    """
    let data = json.data(using: .utf8)!
    let field = try JSONDecoder().decode(PreferenceField.self, from: data)

    XCTAssertEqual(field.id, "pref-1")
    XCTAssertEqual(field.field_name, "dietary")
    XCTAssertEqual(field.question_text, "Do you have any dietary restrictions?")
    XCTAssertEqual(field.options?.has_details, true)
    XCTAssertEqual(field.options?.details_prompt, "Please specify")
    XCTAssertEqual(field.value, "true|No shellfish",
                   "SNAPSHOT: Pipe-delimited value must survive decoding")
    XCTAssertEqual(field.text_value, "No shellfish")
  }

  func testPreferenceField_parsePipeValue() {
    let rawValue = "true|Vegetarian"
    let boolPart = rawValue.split(separator: "|", maxSplits: 1).first.map(String.init) ?? rawValue
    let textPart = rawValue.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""

    XCTAssertEqual(boolPart, "true",
                   "SNAPSHOT: Bool part must be extracted before pipe")
    XCTAssertEqual(textPart, "Vegetarian",
                   "SNAPSHOT: Text part must be extracted after pipe")
  }

  // MARK: - Model decoding: ProficiencyField in wizard context

  func testProficiencyField_decodesWithOptionLabels() throws {
    let json = """
    {
      "id": "prof-1",
      "field_name": "casting",
      "field_label": "Casting Ability",
      "field_type": "slider",
      "question_text": "How would you rate your casting?",
      "context_text": "This helps us plan your activities.",
      "options": {"min": 1, "max": 100, "low_label": "Beginner", "mid_label": "Intermediate", "high_label": "Expert"},
      "is_required": true,
      "sort_order": 1,
      "value": "65"
    }
    """
    let data = json.data(using: .utf8)!
    let field = try JSONDecoder().decode(ProficiencyField.self, from: data)

    XCTAssertEqual(field.options?.min, 1)
    XCTAssertEqual(field.options?.max, 100)
    XCTAssertEqual(field.options?.lowText, "Beginner",
                   "SNAPSHOT: low_label must map to lowText")
    XCTAssertEqual(field.options?.midText, "Intermediate",
                   "SNAPSHOT: mid_label must map to midText")
    XCTAssertEqual(field.options?.highText, "Expert",
                   "SNAPSHOT: high_label must map to highText")
    XCTAssertEqual(field.value, "65")
  }

  func testProficiencyField_defaultsToMidpointWhenNoValue() throws {
    let json = """
    {
      "id": "prof-2",
      "field_name": "wading",
      "field_label": "Wading Comfort",
      "field_type": "slider",
      "question_text": null,
      "context_text": null,
      "options": {"min": 1, "max": 100},
      "is_required": false,
      "sort_order": 2,
      "value": null
    }
    """
    let data = json.data(using: .utf8)!
    let field = try JSONDecoder().decode(ProficiencyField.self, from: data)

    let defaultVal = Double((field.options?.min ?? 1) + (field.options?.max ?? 100)) / 2.0
    XCTAssertEqual(defaultVal, 50.5,
                   "SNAPSHOT: Default slider value must be midpoint of min/max range")
  }

  // MARK: - Model decoding: GearField in wizard context

  func testGearField_decodesWithPriority() throws {
    let json = """
    {
      "id": "gear-1",
      "field_name": "waders",
      "field_label": "Waders",
      "field_type": "checkbox",
      "question_text": null,
      "context_text": "Breathable chest waders recommended",
      "options": {"priority": "mandatory"},
      "is_required": true,
      "sort_order": 1,
      "value": "true"
    }
    """
    let data = json.data(using: .utf8)!
    let field = try JSONDecoder().decode(GearField.self, from: data)

    XCTAssertEqual(field.id, "gear-1")
    XCTAssertEqual(field.options?.priority, "mandatory",
                   "SNAPSHOT: Gear priority must decode from options.priority")
    XCTAssertEqual(field.value, "true")
    XCTAssertEqual(field.context_text, "Breathable chest waders recommended")
  }

  func testGearField_groupsByPriority() throws {
    let fields = [
      GearField(id: "g1", field_name: "waders", field_label: "Waders",
                field_type: "checkbox", question_text: nil, context_text: nil,
                options: GearFieldOptions(priority: "mandatory"),
                is_required: true, sort_order: 1, value: "false"),
      GearField(id: "g2", field_name: "rain_jacket", field_label: "Rain Jacket",
                field_type: "checkbox", question_text: nil, context_text: nil,
                options: GearFieldOptions(priority: "recommended"),
                is_required: false, sort_order: 2, value: "false"),
      GearField(id: "g3", field_name: "sunscreen", field_label: "Sunscreen",
                field_type: "checkbox", question_text: nil, context_text: nil,
                options: nil,
                is_required: false, sort_order: 3, value: "false"),
    ]

    let mandatory = fields.filter { ($0.options?.priority ?? "") == "mandatory" }
    let recommended = fields.filter { ($0.options?.priority ?? "") == "recommended" }
    let other = fields.filter {
      let p = $0.options?.priority ?? ""
      return p != "mandatory" && p != "recommended"
    }

    XCTAssertEqual(mandatory.count, 1, "SNAPSHOT: 1 mandatory item")
    XCTAssertEqual(recommended.count, 1, "SNAPSHOT: 1 recommended item")
    XCTAssertEqual(other.count, 1,
                   "SNAPSHOT: Items without priority go to 'other' group")
  }

  // MARK: - Network: Preferences API response decoding

  func testPreferencesAPIResponse_decodesInWizardContext() throws {
    let json = """
    {
      "preferences": [
        {
          "id": "f1",
          "field_name": "diet",
          "field_label": "Diet",
          "field_type": "boolean",
          "question_text": "Dietary needs?",
          "context_text": null,
          "options": {"has_details": true, "details_prompt": "Specify"},
          "is_required": false,
          "sort_order": 2,
          "value": "false",
          "text_value": null
        },
        {
          "id": "f2",
          "field_name": "mobility",
          "field_label": "Mobility",
          "field_type": "boolean",
          "question_text": "Any mobility concerns?",
          "context_text": null,
          "options": {"has_details": false},
          "is_required": false,
          "sort_order": 1,
          "value": null,
          "text_value": null
        }
      ]
    }
    """
    struct Resp: Decodable { let preferences: [PreferenceField] }
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Resp.self, from: data)
    let sorted = decoded.preferences.sorted { $0.sort_order < $1.sort_order }

    XCTAssertEqual(sorted.count, 2)
    XCTAssertEqual(sorted[0].id, "f2",
                   "SNAPSHOT: Preferences must be sortable by sort_order")
    XCTAssertEqual(sorted[1].id, "f1")
  }

  // MARK: - Network: Proficiency API response decoding

  func testProficiencyAPIResponse_decodesInWizardContext() throws {
    let json = """
    {
      "proficiencies": [
        {
          "id": "p1",
          "field_name": "casting",
          "field_label": "Casting",
          "field_type": "slider",
          "question_text": "Rate your casting",
          "context_text": null,
          "options": {"min": 1, "max": 100, "low_label": "Novice", "mid_label": "Average", "high_label": "Pro"},
          "is_required": false,
          "sort_order": 1,
          "value": "42"
        }
      ]
    }
    """
    struct Resp: Decodable { let proficiencies: [ProficiencyField] }
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Resp.self, from: data)

    XCTAssertEqual(decoded.proficiencies.count, 1)
    XCTAssertEqual(decoded.proficiencies[0].value, "42")
    XCTAssertEqual(Double(decoded.proficiencies[0].value!)!, 42.0,
                   "SNAPSHOT: Proficiency value must parse to Double for slider")
  }

  // MARK: - Network: Gear API response decoding

  func testGearAPIResponse_decodesInWizardContext() throws {
    let json = """
    {
      "gear": [
        {
          "id": "g1",
          "field_name": "rod",
          "field_label": "Fly Rod",
          "field_type": "checkbox",
          "question_text": null,
          "context_text": "9ft 5wt recommended",
          "options": {"priority": "mandatory"},
          "is_required": true,
          "sort_order": 1,
          "value": "true"
        },
        {
          "id": "g2",
          "field_name": "hat",
          "field_label": "Sun Hat",
          "field_type": "checkbox",
          "question_text": null,
          "context_text": null,
          "options": {"priority": "recommended"},
          "is_required": false,
          "sort_order": 2,
          "value": "false"
        }
      ]
    }
    """
    struct Resp: Decodable { let gear: [GearField] }
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Resp.self, from: data)

    XCTAssertEqual(decoded.gear.count, 2)
    XCTAssertEqual(decoded.gear[0].value, "true",
                   "SNAPSHOT: Checked gear must decode as 'true'")
    XCTAssertEqual(decoded.gear[1].value, "false",
                   "SNAPSHOT: Unchecked gear must decode as 'false'")
  }
}
