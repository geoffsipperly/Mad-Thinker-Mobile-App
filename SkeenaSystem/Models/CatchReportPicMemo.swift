// Bend Fly Shop

import CoreLocation
import Foundation

// MARK: - Local status

public enum CatchReportPicMemoStatus: String, Codable, CaseIterable {
  case savedLocally = "Saved locally"
  case uploaded = "Uploaded"
}

// MARK: - Main model

public struct CatchReportPicMemo: Identifiable, Codable, Equatable {
  // Local identity
  public let id: UUID // local ID (for JSON filename, SwiftUI IDs)
  public var createdAt: Date
  public var catchDate: Date?
  public var uploadedAt: Date?

  // Upload status
  public var status: CatchReportPicMemoStatus

  // Catch info (FINAL, after any editing)
  public var anglerNumber: String
  public var species: String?
  public var sex: String?
  public var origin: String?
  public var lengthInches: Int
  public var lifecycleStage: String?
  public var river: String?
  public var classifiedWatersLicenseNumber: String?

  // Location
  public var lat: Double?
  public var lon: Double?

  // Local media references
  /// Filename of the photo under Documents/CatchPhotos (same as existing PhotoStore convention).
  public var photoFilename: String?
  /// ID of the voice note (LocalVoiceNote.id) if there is an attached memo.
  public var voiceNoteId: UUID?

  // 🔊 Voice memo metadata (for v2 voiceMemo object)
  /// Transcribed text from the voice memo (used by AI catch story gen).
  public var voiceTranscript: String?
  /// Language code, e.g. "en-US".
  public var voiceLanguage: String?
  /// Whether transcription was done on-device.
  public var voiceOnDevice: Bool?
  /// Audio sample rate in Hz (e.g. 24000).
  public var voiceSampleRate: Int?
  /// Audio format string: "m4a" or "caf".
  public var voiceFormat: String?

  // Trip info (minimal for now, can be extended later)
  public var tripId: String?
  public var tripName: String?
  public var tripStartDate: Date?
  public var tripEndDate: Date?
  public var guideName: String?
  public var community: String?
  public var lodge: String?

  // Initial AI analysis (for v2 initialAnalysis section)
  public var initialRiverName: String?
  public var initialSpecies: String?
  public var initialLifecycleStage: String?
  public var initialSex: String?
  public var initialLengthInches: Int?

  // Meta
  public var appVersion: String?
  public var deviceDescription: String?
  public var platform: String?

  public init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    catchDate: Date? = nil,
    uploadedAt: Date? = nil,
    status: CatchReportPicMemoStatus = .savedLocally,
    anglerNumber: String,
    species: String? = nil,
    sex: String? = nil,
    origin: String? = nil,
    lengthInches: Int,
    lifecycleStage: String? = nil,
    river: String? = nil,
    classifiedWatersLicenseNumber: String? = nil,
    lat: Double? = nil,
    lon: Double? = nil,
    photoFilename: String? = nil,
    voiceNoteId: UUID? = nil,
    voiceTranscript: String? = nil,
    voiceLanguage: String? = nil,
    voiceOnDevice: Bool? = nil,
    voiceSampleRate: Int? = nil,
    voiceFormat: String? = nil,
    tripId: String? = nil,
    tripName: String? = nil,
    tripStartDate: Date? = nil,
    tripEndDate: Date? = nil,
    guideName: String? = nil,
    community: String? = nil,
    lodge: String? = nil,
    initialRiverName: String? = nil,
    initialSpecies: String? = nil,
    initialLifecycleStage: String? = nil,
    initialSex: String? = nil,
    initialLengthInches: Int? = nil,
    appVersion: String? = nil,
    deviceDescription: String? = nil,
    platform: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.catchDate = catchDate
    self.uploadedAt = uploadedAt
    self.status = status
    self.anglerNumber = anglerNumber
    self.species = species
    self.sex = sex
    self.origin = origin
    self.lengthInches = lengthInches
    self.lifecycleStage = lifecycleStage
    self.river = river
    self.classifiedWatersLicenseNumber = classifiedWatersLicenseNumber
    self.lat = lat
    self.lon = lon
    self.photoFilename = photoFilename
    self.voiceNoteId = voiceNoteId
    self.voiceTranscript = voiceTranscript
    self.voiceLanguage = voiceLanguage
    self.voiceOnDevice = voiceOnDevice
    self.voiceSampleRate = voiceSampleRate
    self.voiceFormat = voiceFormat
    self.tripId = tripId
    self.tripName = tripName
    self.tripStartDate = tripStartDate
    self.tripEndDate = tripEndDate
    self.guideName = guideName
    self.community = community
    self.lodge = lodge
    self.initialRiverName = initialRiverName
    self.initialSpecies = initialSpecies
    self.initialLifecycleStage = initialLifecycleStage
    self.initialSex = initialSex
    self.initialLengthInches = initialLengthInches
    self.appVersion = appVersion
    self.deviceDescription = deviceDescription
    self.platform = platform
  }

  // Convenience
  public var hasPhoto: Bool { photoFilename != nil }
  public var hasVoiceNote: Bool { voiceNoteId != nil }

  public var coordinate: CLLocationCoordinate2D? {
    guard let lat, let lon else { return nil }
    guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  public var isUploaded: Bool { status == .uploaded }
}
