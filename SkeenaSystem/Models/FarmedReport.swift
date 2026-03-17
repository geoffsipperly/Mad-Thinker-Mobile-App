// Bend Fly Shop

import CoreLocation
import Foundation

// MARK: - Status

public enum FarmedReportStatus: String, Codable, CaseIterable {
  case savedLocally = "Saved locally"
  case uploaded = "Uploaded"
}

// MARK: - Model

public struct FarmedReport: Identifiable, Codable, Equatable {
  // Identity
  public let id: UUID
  public var createdAt: Date

  // Status
  public var status: FarmedReportStatus

  // Guide info
  public var guideName: String

  // Location (GPS)
  public var lat: Double?
  public var lon: Double?

  // Optional angler
  public var anglerNumber: String?

  // Convenience
  public var isUploaded: Bool { status == .uploaded }

  public var coordinate: CLLocationCoordinate2D? {
    guard let lat, let lon else { return nil }
    guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
}
