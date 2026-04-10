import XCTest
@testable import SkeenaSystem

/// Tests for CommunityModels Codable decoding from Supabase REST API responses.
final class CommunityModelsTests: XCTestCase {

  // MARK: - CommunityMembership decoding

  func testCommunityMembership_decodesFromJSON() throws {
    let json = """
    {
      "id": "mem-uuid-123",
      "community_id": "comm-uuid-456",
      "role": "guide",
      "is_active": true,
      "communities": {
        "id": "comm-uuid-456",
        "name": "Emerald Waters Anglers",
        "code": "EWA001",
        "is_active": true
      }
    }
    """.data(using: .utf8)!

    let membership = try JSONDecoder().decode(CommunityMembership.self, from: json)

    XCTAssertEqual(membership.id, "mem-uuid-123")
    XCTAssertEqual(membership.communityId, "comm-uuid-456")
    XCTAssertEqual(membership.role, "guide")
    XCTAssertTrue(membership.isActive)
    XCTAssertEqual(membership.communities.id, "comm-uuid-456")
    XCTAssertEqual(membership.communities.name, "Emerald Waters Anglers")
    XCTAssertEqual(membership.communities.code, "EWA001")
    XCTAssertTrue(membership.communities.isActive)
  }

  func testCommunityMembership_decodesAnglerRole() throws {
    let json = """
    {
      "id": "mem-uuid-789",
      "community_id": "comm-uuid-abc",
      "role": "angler",
      "is_active": true,
      "communities": {
        "id": "comm-uuid-abc",
        "name": "Epic Waters",
        "code": "EPW002",
        "is_active": true
      }
    }
    """.data(using: .utf8)!

    let membership = try JSONDecoder().decode(CommunityMembership.self, from: json)
    XCTAssertEqual(membership.role, "angler")
    XCTAssertTrue(membership.isActive)
    XCTAssertEqual(membership.communities.name, "Epic Waters")
  }

  func testCommunityMembership_decodesInactiveCommunity() throws {
    let json = """
    {
      "id": "mem-1",
      "community_id": "comm-inactive",
      "role": "guide",
      "is_active": true,
      "communities": {
        "id": "comm-inactive",
        "name": "Old Community",
        "code": "OLD001",
        "is_active": false
      }
    }
    """.data(using: .utf8)!

    let membership = try JSONDecoder().decode(CommunityMembership.self, from: json)
    XCTAssertTrue(membership.isActive)
    XCTAssertFalse(membership.communities.isActive)
  }

  func testCommunityMembership_decodesInactiveMember() throws {
    let json = """
    {
      "id": "mem-2",
      "community_id": "comm-active",
      "role": "angler",
      "is_active": false,
      "communities": {
        "id": "comm-active",
        "name": "Active Community",
        "code": "ACT001",
        "is_active": true
      }
    }
    """.data(using: .utf8)!

    let membership = try JSONDecoder().decode(CommunityMembership.self, from: json)
    XCTAssertFalse(membership.isActive)
    XCTAssertTrue(membership.communities.isActive)
  }

  func testCommunityMembership_decodesArray() throws {
    let json = """
    [
      {
        "id": "m1",
        "community_id": "c1",
        "role": "guide",
        "is_active": true,
        "communities": { "id": "c1", "name": "Comm A", "code": "AAA111", "is_active": true }
      },
      {
        "id": "m2",
        "community_id": "c2",
        "role": "angler",
        "is_active": true,
        "communities": { "id": "c2", "name": "Comm B", "code": "BBB222", "is_active": true }
      }
    ]
    """.data(using: .utf8)!

    let memberships = try JSONDecoder().decode([CommunityMembership].self, from: json)
    XCTAssertEqual(memberships.count, 2)
    XCTAssertEqual(memberships[0].role, "guide")
    XCTAssertEqual(memberships[1].role, "angler")
  }

  // MARK: - JoinCommunityResponse decoding

  func testJoinCommunityResponse_decodesSuccess() throws {
    let json = """
    {
      "success": true,
      "community_name": "Emerald Waters Anglers",
      "community_id": "uuid-here",
      "role": "angler"
    }
    """.data(using: .utf8)!

    let resp = try JSONDecoder().decode(JoinCommunityResponse.self, from: json)
    XCTAssertEqual(resp.success, true)
    XCTAssertEqual(resp.communityName, "Emerald Waters Anglers")
    XCTAssertEqual(resp.communityId, "uuid-here")
    XCTAssertEqual(resp.role, "angler")
    XCTAssertNil(resp.error)
  }

  func testJoinCommunityResponse_decodesConflict() throws {
    let json = """
    {
      "error": "Already a member of this community",
      "community_name": "Emerald Waters Anglers",
      "role": "guide"
    }
    """.data(using: .utf8)!

    let resp = try JSONDecoder().decode(JoinCommunityResponse.self, from: json)
    XCTAssertNil(resp.success)
    XCTAssertEqual(resp.error, "Already a member of this community")
    XCTAssertEqual(resp.communityName, "Emerald Waters Anglers")
    XCTAssertEqual(resp.role, "guide")
  }

  // MARK: - CommunityInfo decoding

  func testCommunityInfo_identifiable() throws {
    let json = """
    { "id": "test-id", "name": "Test", "code": "TST001", "is_active": true }
    """.data(using: .utf8)!

    let info = try JSONDecoder().decode(CommunityInfo.self, from: json)
    XCTAssertEqual(info.id, "test-id")
    XCTAssertEqual(info.code, "TST001")
  }

  // MARK: - CommunityError

  func testCommunityError_descriptions() {
    XCTAssertNotNil(CommunityError.unauthenticated.errorDescription)
    XCTAssertNotNil(CommunityError.invalidCode.errorDescription)
    XCTAssertNotNil(CommunityError.invalidCodeFormat.errorDescription)
    XCTAssertNotNil(CommunityError.alreadyMember("Test").errorDescription)
    XCTAssertTrue(CommunityError.alreadyMember("Test").errorDescription!.contains("Test"))
    XCTAssertNotNil(CommunityError.serverError(500, "fail").errorDescription)
  }
}
