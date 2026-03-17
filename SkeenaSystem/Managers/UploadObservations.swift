// Bend Fly Shop

import Foundation

// MARK: - Response DTOs (nonisolated to avoid actor isolation issues in Swift 6)

private struct UploadResponseDTO: Sendable {
  let processed: Int
  let successful: Int
  let skipped: Int
  let failed: Int
  let results: [UploadResultDTO]
  let errors: [String]?
}

extension UploadResponseDTO: Decodable {
  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    processed = try container.decode(Int.self, forKey: .processed)
    successful = try container.decode(Int.self, forKey: .successful)
    skipped = try container.decode(Int.self, forKey: .skipped)
    failed = try container.decode(Int.self, forKey: .failed)
    results = try container.decode([UploadResultDTO].self, forKey: .results)
    errors = try container.decodeIfPresent([String].self, forKey: .errors)
  }

  private enum CodingKeys: String, CodingKey {
    case processed, successful, skipped, failed, results, errors
  }
}

private struct UploadResultDTO: Sendable {
  let clientId: String
  let id: String?
  let status: String
}

extension UploadResultDTO: Decodable {
  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    clientId = try container.decode(String.self, forKey: .clientId)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    status = try container.decode(String.self, forKey: .status)
  }

  private enum CodingKeys: String, CodingKey {
    case clientId, id, status
  }
}

// MARK: - Upload service for standalone observations

final class UploadObservations {

  // MARK: - Error types

  enum UploadError: LocalizedError {
    case unauthenticated
    case noObservationsToUpload
    case encodingFailed(String)
    case network(Error)
    case http(Int, String)

    var errorDescription: String? {
      switch self {
      case .unauthenticated:
        return "Not authenticated. Please log in and try again."
      case .noObservationsToUpload:
        return "No pending observations to upload."
      case .encodingFailed(let detail):
        return "Failed to prepare upload: \(detail)"
      case .network(let error):
        return "Network error: \(error.localizedDescription)"
      case .http(let code, let body):
        return "Server error (\(code)): \(body)"
      }
    }
  }

  // MARK: - DTOs (match API contract)

  private struct UploadObservationDTO: Codable {
    let clientId: String
    let createdAt: String
    let language: String
    let onDevice: Bool
    let sampleRate: Int
    let format: String
    let transcript: String
    let location: LocationDTO?
    let audio: AudioDTO

    struct LocationDTO: Codable {
      let lat: Double
      let lon: Double
      let horizontalAccuracy: Double
    }

    struct AudioDTO: Codable {
      let filename: String
      let mimeType: String
      let data_base64: String
    }
  }

  // MARK: - Upload

  func upload(
    observations: [Observation],
    progress: @escaping (Double) -> Void,
    completion: @escaping (Result<[UUID], UploadError>) -> Void
  ) {
    let pending = observations.filter { $0.status == .savedLocally }
    guard !pending.isEmpty else {
      completion(.failure(.noObservationsToUpload))
      return
    }

    guard let jwt = AuthStore.shared.jwt, !jwt.isEmpty else {
      completion(.failure(.unauthenticated))
      return
    }

    // Build DTOs
    var dtos: [UploadObservationDTO] = []
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]

    for (index, obs) in pending.enumerated() {
      progress(Double(index) / Double(pending.count) * 0.5) // 0–50% for prep

      guard let audioDTO = loadAudio(for: obs) else {
        #if DEBUG
        print("[UploadObservations] Skipping observation \(obs.id) — no audio file found")
        #endif
        continue
      }

      let locationDTO: UploadObservationDTO.LocationDTO?
      if let lat = obs.lat, let lon = obs.lon {
        locationDTO = .init(
          lat: lat,
          lon: lon,
          horizontalAccuracy: obs.horizontalAccuracy ?? 0
        )
      } else {
        locationDTO = nil
      }

      let dto = UploadObservationDTO(
        clientId: obs.clientId.uuidString,
        createdAt: isoFormatter.string(from: obs.createdAt),
        language: obs.voiceLanguage ?? "en-US",
        onDevice: obs.voiceOnDevice ?? true,
        sampleRate: obs.voiceSampleRate ?? 16000,
        format: obs.voiceFormat ?? "m4a",
        transcript: obs.transcript,
        location: locationDTO,
        audio: audioDTO
      )
      dtos.append(dto)
    }

    guard !dtos.isEmpty else {
      completion(.failure(.encodingFailed("No observations could be prepared (missing audio files)")))
      return
    }

    // Encode
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]

    let bodyData: Data
    do {
      bodyData = try encoder.encode(dtos)
    } catch {
      completion(.failure(.encodingFailed(error.localizedDescription)))
      return
    }

    // Build request
    let endpoint = AppEnvironment.shared.observationsURL
    let apiKey = AppEnvironment.shared.anonKey

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    request.timeoutInterval = 60

    progress(0.5) // 50% — sending

    // Send
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error {
        DispatchQueue.main.async { completion(.failure(.network(error))) }
        return
      }

      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

      guard statusCode == 200 else {
        DispatchQueue.main.async { completion(.failure(.http(statusCode, body))) }
        return
      }

      // Parse response
      var uploadedClientIds: [UUID] = []
      if let data, let resp = try? JSONDecoder().decode(UploadResponseDTO.self, from: data) {
        for result in resp.results where result.status == "success" || result.status == "skipped" {
          if let uuid = UUID(uuidString: result.clientId) {
            uploadedClientIds.append(uuid)
          }
        }
      }

      DispatchQueue.main.async {
        progress(1.0)
        completion(.success(uploadedClientIds))
      }
    }
    .resume()
  }

  // MARK: - Audio loading

  private func loadAudio(for observation: Observation) -> UploadObservationDTO.AudioDTO? {
    guard let voiceNoteId = observation.voiceNoteId else { return nil }

    // Find the audio file via VoiceNoteStore
    let store = VoiceNoteStore.shared
    let audioURL = store.audioURL(for: LocalVoiceNote(
      id: voiceNoteId,
      createdAt: Date(),
      durationSec: nil,
      language: "en-US",
      onDevice: true,
      sampleRate: 16000,
      format: "m4a",
      transcript: "",
      lat: nil,
      lon: nil,
      horizontalAccuracy: nil,
      status: .savedPendingUpload
    ))

    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      // Fallback: try pattern-based lookup
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let fallback = docs
        .appendingPathComponent("VoiceNotes", isDirectory: true)
        .appendingPathComponent("note_\(voiceNoteId.uuidString).m4a")

      guard FileManager.default.fileExists(atPath: fallback.path),
            let data = try? Data(contentsOf: fallback) else {
        return nil
      }

      return UploadObservationDTO.AudioDTO(
        filename: fallback.lastPathComponent,
        mimeType: "audio/m4a",
        data_base64: data.base64EncodedString()
      )
    }

    guard let data = try? Data(contentsOf: audioURL) else { return nil }

    let ext = audioURL.pathExtension.lowercased()
    let mimeType = ext == "caf" ? "audio/x-caf" : "audio/m4a"

    return UploadObservationDTO.AudioDTO(
      filename: audioURL.lastPathComponent,
      mimeType: mimeType,
      data_base64: data.base64EncodedString()
    )
  }
}
