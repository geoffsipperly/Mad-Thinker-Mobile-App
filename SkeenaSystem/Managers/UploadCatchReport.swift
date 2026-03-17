// Bend Fly Shop

import Foundation
import UIKit

final class UploadCatchPicMemo {
  // MARK: - Config

  struct Config {
    let endpoint: URL
    let appVersion: String
    let deviceDescription: String
    let platform: String
    let timeout: TimeInterval
    let apiKey: String

    init(
      endpoint: URL,
      appVersion: String,
      deviceDescription: String = "\(UIDevice.current.model) \(UIDevice.current.systemVersion)",
      platform: String = "iOS",
      timeout: TimeInterval = 30,
      apiKey: String
    ) {
      self.endpoint = endpoint
      self.appVersion = appVersion
      self.deviceDescription = deviceDescription
      self.platform = platform
      self.timeout = timeout
      self.apiKey = apiKey
    }
  }

  enum UploadError: LocalizedError {
    case unauthenticated
    case noReportsToUpload
    case localValidationFailed([String])
    case encodingFailed(String)
    case network(Error)
    case http(Int, String)

    var errorDescription: String? {
      switch self {
      case .unauthenticated:
        "You must be signed in to upload catch reports"
      case .noReportsToUpload:
        "There are no pending catch reports to upload."
      case let .localValidationFailed(messages):
        "Some catch reports failed validation:\n" + messages.joined(separator: "\n")
      case let .encodingFailed(message):
        "Failed to encode catch report upload payload: \(message)"
      case let .network(error):
        "Network error while uploading catch reports: \(error.localizedDescription)"
      case let .http(status, body):
        "Server returned HTTP \(status) for catch upload: \(body)"
      }
    }
  }

  // MARK: - DTOs

  private struct UploadCatchPicMemoDTO: Codable {
    let reportId: String
    let createdAt: Date
    let uploadedAt: Date
    let tripId: String?
    let tripName: String?
    let catchInfo: CatchDTO
    let initialAnalysis: InitialAnalysisDTO?
    let status: String
    let meta: MetaDTO

    enum CodingKeys: String, CodingKey {
      case reportId, createdAt, uploadedAt, tripId, tripName
      case catchInfo = "catch"
      case initialAnalysis, status, meta
    }
  }

  private struct CatchDTO: Codable {
    let anglerNumber: String
    let species: String?
    let sex: String?
    let origin: String?
    let lengthInches: Int
    let lifecycleStage: String?
    let river: String?
    let classifiedWatersLicenseNumber: String?
    let location: Location?
    let photo: Photo?
    let voiceMemo: VoiceMemo?

    struct Location: Codable {
      let lat: Double
      let lon: Double
    }

    struct Photo: Codable {
      let filename: String
      let mimeType: String
      let data_base64: String
    }

    struct VoiceMemo: Codable {
      let filename: String
      let mimeType: String
      let data_base64: String
      let transcript: String
      let language: String
      let onDevice: Bool
      let sampleRate: Int
      let format: String
    }
  }

  private struct InitialAnalysisDTO: Codable {
    let riverName: String?
    let species: String?
    let lifecycleStage: String?
    let sex: String?
    let lengthInches: Int?
  }

  private struct MetaDTO: Codable {
    let appVersion: String
    let device: String
    let platform: String
  }

  nonisolated private struct ResponseDTO: Codable {
    // V3 fields
    let version: String?
    let processed: Int
    let successful: Int
    let skipped: Int?
    let failed: Int
    let results: [ResponseResultDTO]?
    let errors: [String]?

    // V2 compatibility
    let success: Bool?
  }

  nonisolated private struct ResponseResultDTO: Codable {
    let reportId: String
    let status: String
    // V3 fields
    let id: String?
    let tripId: String?
    let originalTripId: String?
    let tripReconciled: Bool?
    let anglerId: String?
    // V2 compatibility
    let catchReportId: String?
  }

  // MARK: - Validation (testable without instantiation)

  /// Filters reports to only those with `.savedLocally` status.
  static func filterPending(_ reports: [CatchReportPicMemo]) -> [CatchReportPicMemo] {
    reports.filter { $0.status == .savedLocally }
  }

  /// Validates a single report's fields. Returns error messages, or empty array if valid.
  static func validateReport(_ report: CatchReportPicMemo) -> [String] {
    var errors: [String] = []
    let anglerNumber = report.anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    if anglerNumber.isEmpty {
      errors.append("• \(report.id.uuidString): anglerNumber is required")
    }
    if report.lengthInches < 1 {
      errors.append("• \(report.id.uuidString): lengthInches must be at least 1")
    }
    return errors
  }

  /// Runs the full pre-upload validation pipeline and returns the first error encountered, or nil if valid.
  /// Mirrors the guard/validation sequence in `upload()` without requiring an instance or network call.
  static func validateForUpload(reports: [CatchReportPicMemo], jwt: String?) -> UploadError? {
    let pending = filterPending(reports)
    guard !pending.isEmpty else { return .noReportsToUpload }
    guard let jwt, !jwt.isEmpty else { return .unauthenticated }
    var allErrors: [String] = []
    for report in pending {
      allErrors.append(contentsOf: validateReport(report))
    }
    if !allErrors.isEmpty { return .localValidationFailed(allErrors) }
    return nil
  }

  // MARK: - Properties

  private let config: Config
  private let session: URLSession

  init(config: Config, session: URLSession? = nil) {
    self.config = config

    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = config.timeout
      configuration.timeoutIntervalForResource = config.timeout
      self.session = URLSession(configuration: configuration)
    }
  }

  // MARK: - Public API

  func upload(
    reports: [CatchReportPicMemo],
    progress: @escaping (Double) -> Void,
    completion: @escaping (Result<[UUID], Error>) -> Void
  ) {
    let pending = reports.filter { $0.status == .savedLocally }

    guard !pending.isEmpty else {
      completion(.failure(UploadError.noReportsToUpload))
      return
    }

    guard let jwt = AuthStore.shared.jwt, !jwt.isEmpty else {
      completion(.failure(UploadError.unauthenticated))
      return
    }

    let now = Date()
    var dtos: [UploadCatchPicMemoDTO] = []
    var errors: [String] = []

    for report in pending {
      do {
        let dto = try makeDTO(from: report, now: now)
        dtos.append(dto)
      } catch let UploadError.localValidationFailed(messages) {
        errors.append(contentsOf: messages)
      } catch {
        errors.append("• \(report.id.uuidString): \(error.localizedDescription)")
      }
    }

    if !errors.isEmpty {
      completion(.failure(UploadError.localValidationFailed(errors)))
      return
    }

    guard !dtos.isEmpty else {
      completion(.failure(UploadError.noReportsToUpload))
      return
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes, .prettyPrinted]

    let bodyData: Data
    do {
      bodyData = try encoder.encode(dtos)

      if let jsonString = String(data: bodyData, encoding: .utf8) {
        let preview = jsonString.count > 4000
          ? String(jsonString.prefix(4000)) + "\n…(truncated)…"
          : jsonString

        AppLogging.log({ "================ V3 UPLOAD REQUEST PAYLOAD ================" }, level: .debug, category: .network)
        AppLogging.log({ "Size: \(bodyData.count) bytes, chars: \(jsonString.count)" }, level: .debug, category: .network)
        AppLogging.log({ preview }, level: .debug, category: .network)
        AppLogging.log({ "===========================================================" }, level: .debug, category: .network)
      }
    } catch {
      completion(.failure(UploadError.encodingFailed(error.localizedDescription)))
      return
    }

    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

    #if DEBUG
    AppLogging.log({ "[UploadCatchPicMemo] POST \(config.endpoint.absoluteString)" }, level: .debug, category: .network)
    AppLogging.log({ "[UploadCatchPicMemo] Body size: \(bodyData.count) bytes" }, level: .debug, category: .network)
    #endif

    progress(0.1)

    let task = session.dataTask(with: request) { data, response, error in
      if let error {
        DispatchQueue.main.async {
          completion(.failure(UploadError.network(error)))
        }
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        DispatchQueue.main.async {
          completion(.failure(UploadError.http(-1, "No HTTP response")))
        }
        return
      }

      let statusCode = httpResponse.statusCode
      let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Response \(statusCode)" }, level: .debug, category: .network)
      AppLogging.log({ "[UploadCatchPicMemo] Body:\n\(responseBody)" }, level: .debug, category: .network)
      #endif

      guard (200 ... 299).contains(statusCode) else {
        DispatchQueue.main.async {
          completion(.failure(UploadError.http(statusCode, responseBody)))
        }
        return
      }

      var uploadedIDs: [UUID] = []

      if let data {
        do {
          let decoder = JSONDecoder()
          let resp = try decoder.decode(ResponseDTO.self, from: data)
          #if DEBUG
          let v = resp.version ?? "unknown"
          AppLogging.log({ "[UploadCatchPicMemo] Parsed response: version=\(v), processed=\(resp.processed), successful=\(resp.successful), failed=\(resp.failed)" }, level: .debug, category: .network)
          if let reconciled = resp.results?.filter({ $0.tripReconciled == true }), !reconciled.isEmpty {
            AppLogging.log({ "[UploadCatchPicMemo] Trip reconciled for \(reconciled.count) report(s)" }, level: .debug, category: .network)
          }
          #endif

          let idsByString = Dictionary(uniqueKeysWithValues: pending.map { ($0.id.uuidString, $0.id) })
          resp.results?.forEach { result in
            if result.status == "success", let localId = idsByString[result.reportId] {
              uploadedIDs.append(localId)
            }
          }

          // Fallback: if we couldn't match individual results but the overall response was successful
          let isSuccess = resp.success ?? (resp.successful > 0 && resp.failed == 0)
          if uploadedIDs.isEmpty, isSuccess {
            uploadedIDs = pending.map(\.id)
          }
        } catch {
          #if DEBUG
          AppLogging.log({ "[UploadCatchPicMemo] Failed to decode response JSON: \(error.localizedDescription)" }, level: .warn, category: .network)
          #endif
          uploadedIDs = pending.map(\.id)
        }
      } else {
        uploadedIDs = pending.map(\.id)
      }

      DispatchQueue.main.async {
        progress(1.0)
        completion(.success(uploadedIDs))
      }
    }

    task.resume()
  }

  // MARK: - Mapping

  private func makeDTO(from r: CatchReportPicMemo, now: Date) throws -> UploadCatchPicMemoDTO {
    var localErrors: [String] = []

    let anglerNumber = r.anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    if anglerNumber.isEmpty {
      localErrors.append("anglerNumber is required")
    }

    if r.lengthInches < 1 {
      localErrors.append("lengthInches must be at least 1")
    }

    if !localErrors.isEmpty {
      throw UploadError.localValidationFailed(
        localErrors.map { "• \(r.id.uuidString): \($0)" }
      )
    }

    let createdAt = r.catchDate ?? r.createdAt
    let uploadedAt = r.uploadedAt ?? now

    // Location
    var location: CatchDTO.Location?
    if let lat = r.lat, let lon = r.lon, abs(lat) <= 90, abs(lon) <= 180 {
      location = .init(lat: lat, lon: lon)
    }

    // Photo
    let photo = try loadPhoto(from: r)

    // Voice memo (with real transcript + metadata)
    let voiceMemo = try loadVoiceMemo(from: r)

    // Initial analysis
    let initial = InitialAnalysisDTO(
      riverName: r.initialRiverName,
      species: r.initialSpecies,
      lifecycleStage: r.initialLifecycleStage,
      sex: r.initialSex,
      lengthInches: r.initialLengthInches
    )

    #if DEBUG
    let tripIdDebug = r.tripId ?? "(nil)"
    let tripNameDebug = r.tripName ?? "(nil)"
    AppLogging.log({ "[UploadCatchPicMemo] Mapping V3 for report=\(r.id): tripId=\(tripIdDebug), tripName=\(tripNameDebug)" }, level: .debug, category: .network)
    #endif

    let tripIdToSend = r.tripId
    let tripNameToSend = r.tripName

    let meta = MetaDTO(
      appVersion: r.appVersion ?? config.appVersion,
      device: r.deviceDescription ?? config.deviceDescription,
      platform: r.platform ?? config.platform
    )

    let catchDTO = CatchDTO(
      anglerNumber: anglerNumber,
      species: r.species,
      sex: r.sex,
      origin: r.origin,
      lengthInches: max(1, r.lengthInches),
      lifecycleStage: r.lifecycleStage,
      river: r.river,
      classifiedWatersLicenseNumber: r.classifiedWatersLicenseNumber,
      location: location,
      photo: photo,
      voiceMemo: voiceMemo
    )

    return UploadCatchPicMemoDTO(
      reportId: r.id.uuidString,
      createdAt: createdAt,
      uploadedAt: uploadedAt,
      tripId: tripIdToSend,
      tripName: tripNameToSend,
      catchInfo: catchDTO,
      initialAnalysis: initial,
      status: r.status == .uploaded ? "Uploaded" : "Saved locally",
      meta: meta
    )
  }

  private func loadPhoto(from report: CatchReportPicMemo) throws -> CatchDTO.Photo? {
    guard let filename = report.photoFilename, !filename.isEmpty else {
      return nil
    }

    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }

    let photosDir = docs.appendingPathComponent("CatchPhotos", isDirectory: true)
    let url = photosDir.appendingPathComponent(filename)

    guard fm.fileExists(atPath: url.path) else {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Photo not found at \(url.path)" }, level: .debug, category: .network)
      #endif
      return nil
    }

    let data = try Data(contentsOf: url)
    let base64 = data.base64EncodedString()
    return CatchDTO.Photo(
      filename: filename,
      mimeType: "image/jpeg",
      data_base64: base64
    )
  }

  // MARK: - Voice memo loading (REAL transcript + metadata)

  private func loadVoiceMemo(from report: CatchReportPicMemo) throws -> CatchDTO.VoiceMemo? {
    guard let noteId = report.voiceNoteId else {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] No voiceNoteId for report \(report.id)" }, level: .debug, category: .audio)
      #endif
      return nil
    }

    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Could not resolve documents directory" }, level: .debug, category: .audio)
      #endif
      return nil
    }

    let notesDir = docs.appendingPathComponent("VoiceNotes", isDirectory: true)

    #if DEBUG
    AppLogging.log({ "[UploadCatchPicMemo] Looking for voice memo for id=\(noteId.uuidString)" }, level: .debug, category: .audio)
    AppLogging.log({ "[UploadCatchPicMemo] Expected directory: \(notesDir.path)" }, level: .debug, category: .audio)
    #endif

    // Try to find the LocalVoiceNote so we can use *its* metadata + transcript.
    let note = VoiceNoteStore.shared.notes.first(where: { $0.id == noteId })

    var candidateURLs: [(URL, String)] = [] // (url, mime)

    if let note {
      let url = VoiceNoteStore.shared.audioURL(for: note)
      let ext = url.pathExtension.lowercased()
      let mime = (ext == "caf") ? "audio/x-caf" : "audio/m4a"

      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Using VoiceNoteStore URL: \(url.path)" }, level: .debug, category: .audio)
      #endif
      candidateURLs.append((url, mime))
    }

    // Fallback: derive from pattern note_<UUID>.m4a / .caf
    let fallbackM4A = notesDir.appendingPathComponent("note_\(noteId.uuidString).m4a")
    let fallbackCAF = notesDir.appendingPathComponent("note_\(noteId.uuidString).caf")
    candidateURLs.append((fallbackM4A, "audio/m4a"))
    candidateURLs.append((fallbackCAF, "audio/x-caf"))

    var finalURL: URL?
    var finalMime = "audio/m4a"

    for (url, mime) in candidateURLs {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Checking \(url.path)" }, level: .debug, category: .audio)
      #endif
      if fm.fileExists(atPath: url.path) {
        finalURL = url
        finalMime = mime
        break
      }
    }

    guard let url = finalURL else {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] No voice memo file found for id=\(noteId.uuidString) in \(notesDir.path)" }, level: .debug, category: .audio)
      #endif
      return nil
    }

    let data = try Data(contentsOf: url)
    guard !data.isEmpty else {
      #if DEBUG
      AppLogging.log({ "[UploadCatchPicMemo] Voice memo file is empty at \(url.path)" }, level: .debug, category: .audio)
      #endif
      return nil
    }

    let base64 = data.base64EncodedString()
    let ext = url.pathExtension.lowercased()
    let inferredFormat = (ext == "caf") ? "caf" : "m4a"

    // === REAL transcript & metadata ===

    // Prefer the transcript from LocalVoiceNote
    var transcript: String? = note?.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if let t = transcript, t.isEmpty { transcript = nil }

    // If not present, fall back to any transcript stored on the report itself
    if transcript == nil,
       let t = report.voiceTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
       !t.isEmpty {
      transcript = t
    }

    // As a last resort, keep a short generic line (should be rare)
    let finalTranscript = transcript ?? "Spoken catch notes for report \(report.id.uuidString)."

    let language = note?.language ?? report.voiceLanguage ?? "en-US"
    let onDevice = note?.onDevice ?? report.voiceOnDevice ?? true
    let sampleRate = Int(note?.sampleRate ?? Double(report.voiceSampleRate ?? 24000))
    let format = report.voiceFormat ?? inferredFormat

    #if DEBUG
    AppLogging.log({ "[UploadCatchPicMemo] Loaded voice memo \(url.lastPathComponent) (\(data.count) bytes)" }, level: .debug, category: .audio)
    AppLogging.log({ "[UploadCatchPicMemo]   transcript: \(finalTranscript.prefix(80))\(finalTranscript.count > 80 ? "…" : "")" }, level: .debug, category: .audio)
    AppLogging.log({ "[UploadCatchPicMemo]   language: \(language), onDevice: \(onDevice), sampleRate: \(sampleRate), format: \(format)" },
      level: .debug, category: .audio
    )
    #endif

    return CatchDTO.VoiceMemo(
      filename: url.lastPathComponent,
      mimeType: finalMime,
      data_base64: base64,
      transcript: finalTranscript,
      language: language,
      onDevice: onDevice,
      sampleRate: sampleRate,
      format: format
    )
  }
}
