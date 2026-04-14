// Bend Fly Shop

import CoreLocation
import Foundation

// MARK: - Status

public enum FarmedReportStatus: String, Codable, CaseIterable {
  case savedLocally = "Saved locally"
  case uploaded = "Uploaded"
}

// MARK: - Event Type

public enum NoCatchEventType: String, Codable, CaseIterable {
  case active    // Fish seen/active but not hooked
  case farmed    // Hooked but not landed
  case promising // Promising conditions observed
  case passed    // Spot checked, nothing observed

  public var displayName: String {
    switch self {
    case .active:    return "Active"
    case .farmed:    return "Farmed"
    case .promising: return "Promising"
    case .passed:    return "Passed"
    }
  }
}

// MARK: - Model

public struct FarmedReport: Identifiable, Codable, Equatable {
  // Identity
  public let id: UUID
  public var createdAt: Date

  // Status
  public var status: FarmedReportStatus

  // Event type (defaults to .farmed for backward compatibility)
  public var eventType: NoCatchEventType

  // Guide info
  public var guideName: String

  // Location (GPS)
  public var lat: Double?
  public var lon: Double?

  // Optional angler
  public var memberId: String?

  /// Active community at the time the report was created. Required for the
  /// per-member/per-community storage scoping in `FarmedReportStore`. Optional
  /// in the model so that legacy JSON on disk (which predates this field) can
  /// still be decoded — the migration path drops such records.
  public var communityId: String?

  // Coding keys with default for backward compatibility with existing JSON on disk
  enum CodingKeys: String, CodingKey {
    case id, createdAt, status, eventType, guideName, lat, lon, memberId, communityId
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    status = try container.decode(FarmedReportStatus.self, forKey: .status)
    eventType = try container.decodeIfPresent(NoCatchEventType.self, forKey: .eventType) ?? .farmed
    guideName = try container.decode(String.self, forKey: .guideName)
    lat = try container.decodeIfPresent(Double.self, forKey: .lat)
    lon = try container.decodeIfPresent(Double.self, forKey: .lon)
    memberId = try container.decodeIfPresent(String.self, forKey: .memberId)
    communityId = try container.decodeIfPresent(String.self, forKey: .communityId)
  }

  public init(
    id: UUID,
    createdAt: Date,
    status: FarmedReportStatus,
    eventType: NoCatchEventType = .farmed,
    guideName: String,
    lat: Double? = nil,
    lon: Double? = nil,
    memberId: String? = nil,
    communityId: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.status = status
    self.eventType = eventType
    self.guideName = guideName
    self.lat = lat
    self.lon = lon
    self.memberId = memberId
    self.communityId = communityId
  }

  // Convenience
  public var isUploaded: Bool { status == .uploaded }

  public var coordinate: CLLocationCoordinate2D? {
    guard let lat, let lon else { return nil }
    guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
}
