// Bend Fly Shop

import Combine
import Foundation

final class CatchReportPicMemoStore: ObservableObject {
  static let shared = CatchReportPicMemoStore()

  @Published private(set) var reports: [CatchReportPicMemo] = []

  private let fm = FileManager.default
  private let directoryURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private init() {
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    self.directoryURL = docs.appendingPathComponent("CatchReportsPicMemo", isDirectory: true)

    self.encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    self.decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    ensureDirectory()
    loadAll()
  }

  // MARK: - Public API

  func refresh() {
    loadAll()
  }

  func add(_ report: CatchReportPicMemo) {
    var new = report
    new.status = .savedLocally
    save(report: new)
    loadAll()
  }

  func update(_ report: CatchReportPicMemo) {
    save(report: report)
    loadAll()
  }

  func delete(_ report: CatchReportPicMemo) {
    let url = jsonURL(for: report.id)
    try? fm.removeItem(at: url)
    loadAll()
  }

  func markUploaded(_ reportIDs: [UUID]) {
    var changed = false
    var current = reports
    let now = Date()

    for idx in current.indices {
      if reportIDs.contains(current[idx].id) {
        current[idx].status = .uploaded
        current[idx].uploadedAt = now
        save(report: current[idx])
        changed = true
      }
    }

    if changed {
      loadAll()
    }
  }

  // MARK: - Convenience creation for chat flow

  /// Create and persist a new PicMemo report from the chat-based capture flow.
  /// This is the preferred entry point to ensure voice memos, photo, trip & analysis
  /// are all captured in one place.
  func createFromChat(
    anglerNumber: String,
    species: String?,
    sex: String?,
    origin: String?,
    lengthInches: Int,
    lifecycleStage: String?,
    river: String?,
    classifiedWatersLicenseNumber: String?,
    lat: Double?,
    lon: Double?,
    photoFilename: String?,
    voiceNoteId: UUID?,
    tripId: String?,
    tripName: String?,
    tripStartDate: Date?,
    tripEndDate: Date?,
    guideName: String?,
    community: String?,
    lodge: String?,
    initialRiverName: String?,
    initialSpecies: String?,
    initialLifecycleStage: String?,
    initialSex: String?,
    initialLengthInches: Int?,
    appVersion: String?,
    deviceDescription: String?,
    platform: String?,
    catchDate: Date? = nil
  ) {
    let report = CatchReportPicMemo(
      id: UUID(),
      createdAt: Date(),
      catchDate: catchDate,
      uploadedAt: nil,
      status: .savedLocally,
      anglerNumber: anglerNumber,
      species: species,
      sex: sex,
      origin: origin,
      lengthInches: lengthInches,
      lifecycleStage: lifecycleStage,
      river: river,
      classifiedWatersLicenseNumber: classifiedWatersLicenseNumber,
      lat: lat,
      lon: lon,
      photoFilename: photoFilename,
      voiceNoteId: voiceNoteId,
      tripId: tripId,
      tripName: tripName,
      tripStartDate: tripStartDate,
      tripEndDate: tripEndDate,
      guideName: guideName,
      community: community,
      lodge: lodge,
      initialRiverName: initialRiverName,
      initialSpecies: initialSpecies,
      initialLifecycleStage: initialLifecycleStage,
      initialSex: initialSex,
      initialLengthInches: initialLengthInches,
      appVersion: appVersion,
      deviceDescription: deviceDescription,
      platform: platform
    )

    save(report: report)
    loadAll()
  }

  /// Optionally attach or change the voice note ID for an existing report.
  func updateVoiceNote(for reportId: UUID, voiceNoteId: UUID?) {
    var changed = false
    var current = reports

    for idx in current.indices {
      if current[idx].id == reportId {
        current[idx].voiceNoteId = voiceNoteId
        save(report: current[idx])
        changed = true
        break
      }
    }

    if changed {
      loadAll()
    }
  }

  // MARK: - Internals

  private func ensureDirectory() {
    if !fm.fileExists(atPath: directoryURL.path) {
      try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }
  }

  private func jsonURL(for id: UUID) -> URL {
    directoryURL.appendingPathComponent("report_\(id.uuidString).json")
  }

  private func save(report: CatchReportPicMemo) {
    ensureDirectory()
    let url = jsonURL(for: report.id)
    do {
      let data = try encoder.encode(report)
      try data.write(to: url, options: [.atomic])
    } catch {
      #if DEBUG
      print("[CatchReportPicMemoStore] Failed to save report \(report.id): \(error.localizedDescription)")
      #endif
    }
  }

  private func loadAll() {
    ensureDirectory()
    guard let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
      DispatchQueue.main.async { self.reports = [] }
      return
    }

    var loaded: [CatchReportPicMemo] = []

    for file in files where file.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: file)
        let report = try decoder.decode(CatchReportPicMemo.self, from: data)
        loaded.append(report)
      } catch {
        #if DEBUG
        print("[CatchReportPicMemoStore] Failed to decode \(file.lastPathComponent): \(error.localizedDescription)")
        #endif
      }
    }

    // Sort newest first
    loaded.sort { $0.createdAt > $1.createdAt }

    DispatchQueue.main.async {
      #if DEBUG
      print("=== PicMemo Store Loaded \(loaded.count) reports ===")
      for r in loaded {
        print("• \(r.id)  hasVoiceNote=\(r.hasVoiceNote)  voiceNoteId=\(String(describing: r.voiceNoteId))")
      }
      print("==============================================")
      #endif

      self.reports = loaded
    }
  }
}
