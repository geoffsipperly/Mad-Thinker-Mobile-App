// Bend Fly Shop

import CoreLocation
import Foundation
import UIKit

// MARK: - Upload service for farmed reports

final class UploadFarmedReports {

  // MARK: - Error types

  enum UploadError: LocalizedError {
    case unauthenticated
    case noReportsToUpload
    case encodingFailed(String)
    case network(Error)
    case http(Int, String)

    var errorDescription: String? {
      switch self {
      case .unauthenticated:
        return "You must be signed in to upload farmed reports."
      case .noReportsToUpload:
        return "No pending farmed reports to upload."
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

  private struct FarmedReportDTO: Codable {
    let reportId: String
    let createdAt: String
    let latitude: Double
    let longitude: Double
    let anglerNumber: String?
    let guideName: String?
    let river: String
    let meta: MetaDTO
  }

  private struct MetaDTO: Codable {
    let appVersion: String
    let device: String?
    let platform: String?
  }

  // MARK: - Response DTOs

  private nonisolated struct ResponseDTO: Decodable {
    let success: Bool?
    let processed: Int
    let successful: Int
    let failed: Int
    let results: [ResponseResultDTO]?
  }

  private nonisolated struct ResponseResultDTO: Decodable {
    let reportId: String
    let status: String
    let farmedReportId: String?
  }

  // MARK: - Properties

  private let session: URLSession

  init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      self.session = URLSession.shared
    }
  }

  // MARK: - Constants

  private static var endpoint: URL {
    AppEnvironment.shared.projectURL.appendingPathComponent("functions/v1/upload-farmed-reports")
  }

  private static var apiKey: String {
    AppEnvironment.shared.anonKey
  }

  // MARK: - Validation (testable without instantiation)

  /// Filters reports to only those with `.savedLocally` status.
  static func filterPending(_ reports: [FarmedReport]) -> [FarmedReport] {
    reports.filter { $0.status == .savedLocally }
  }

  /// Filters pending reports to only those with valid GPS coordinates (both lat and lon non-nil).
  static func filterWithGPS(_ reports: [FarmedReport]) -> [FarmedReport] {
    reports.filter { $0.lat != nil && $0.lon != nil }
  }

  /// Runs the full pre-upload validation pipeline and returns the first error encountered, or nil if valid.
  /// This mirrors the guard sequence in `upload()` without requiring an instance or network call.
  static func validateForUpload(reports: [FarmedReport], jwt: String?) -> UploadError? {
    let pending = filterPending(reports)
    guard !pending.isEmpty else { return .noReportsToUpload }
    guard let jwt, !jwt.isEmpty else { return .unauthenticated }
    let withGPS = filterWithGPS(pending)
    guard !withGPS.isEmpty else { return .encodingFailed("No reports have GPS coordinates") }
    return nil
  }

  /// Resolves a river name from GPS coordinates using the RiverLocator spine dataset.
  /// Falls back to `AppEnvironment.shared.defaultRiver` when no river is within range.
  static func resolveRiverName(lat: Double, lon: Double) -> String {
    let location = CLLocation(latitude: lat, longitude: lon)
    let name = RiverLocator.shared.riverName(near: location)
    if name.isEmpty {
      return WaterBodyLocator.shared.waterBodyName(at: location)
             ?? AppEnvironment.shared.defaultRiver
    }
    return name
  }

  // MARK: - Upload

  func upload(
    reports: [FarmedReport],
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

    // Filter to reports with GPS coordinates
    let withGPS = pending.filter { $0.lat != nil && $0.lon != nil }

    #if DEBUG
    let skipped = pending.count - withGPS.count
    if skipped > 0 {
      for report in pending where report.lat == nil || report.lon == nil {
        print("[UploadFarmedReports] Skipping report \(report.id) — no GPS coordinates")
      }
    }
    #endif

    guard !withGPS.isEmpty else {
      completion(.failure(UploadError.encodingFailed("No reports have GPS coordinates")))
      return
    }

    // Build DTOs (only after confirming we have reports to send)
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    let device = "\(UIDevice.current.model) \(UIDevice.current.systemVersion)"

    let dtos: [FarmedReportDTO] = withGPS.map { report in
      let river = Self.resolveRiverName(lat: report.lat!, lon: report.lon!)
      return FarmedReportDTO(
        reportId: report.id.uuidString,
        createdAt: isoFormatter.string(from: report.createdAt),
        latitude: report.lat!,
        longitude: report.lon!,
        anglerNumber: report.anglerNumber,
        guideName: report.guideName,
        river: river,
        meta: MetaDTO(
          appVersion: appVersion,
          device: device,
          platform: "iOS"
        )
      )
    }

    // Encode
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]

    let bodyData: Data
    do {
      bodyData = try encoder.encode(dtos)
    } catch {
      completion(.failure(UploadError.encodingFailed(error.localizedDescription)))
      return
    }

    #if DEBUG
    if let jsonString = String(data: bodyData, encoding: .utf8) {
      AppLogging.log("[UploadFarmedReports] Payload (\(bodyData.count) bytes):\n\(jsonString.prefix(2000))", level: .debug, category: .network)
    }
    #endif

    // Build request
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    request.setValue(Self.apiKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    request.timeoutInterval = 30

    progress(0.1)

    // Send
    session.dataTask(with: request) { data, response, error in
      if let error {
        DispatchQueue.main.async { completion(.failure(UploadError.network(error))) }
        return
      }

      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

      #if DEBUG
      AppLogging.log("[UploadFarmedReports] Response \(statusCode): \(body.prefix(1000))", level: .debug, category: .network)
      #endif

      guard (200...299).contains(statusCode) else {
        DispatchQueue.main.async { completion(.failure(UploadError.http(statusCode, body))) }
        return
      }

      // Parse response to find which reports succeeded
      var uploadedIDs: [UUID] = []
      let idsByString = Dictionary(uniqueKeysWithValues: pending.map { ($0.id.uuidString, $0.id) })

      if let data, let resp = try? JSONDecoder().decode(ResponseDTO.self, from: data) {
        resp.results?.forEach { result in
          if result.status == "success", let localId = idsByString[result.reportId] {
            uploadedIDs.append(localId)
          }
        }

        // Fallback: if overall success but couldn't match individual results
        let isSuccess = resp.success ?? (resp.successful > 0 && resp.failed == 0)
        if uploadedIDs.isEmpty, isSuccess {
          uploadedIDs = pending.map(\.id)
        }
      } else {
        // If we can't parse but got 2xx, assume all succeeded
        uploadedIDs = pending.map(\.id)
      }

      DispatchQueue.main.async {
        progress(1.0)
        completion(.success(uploadedIDs))
      }
    }
    .resume()
  }
}
