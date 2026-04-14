// Bend Fly Shop

import Foundation

struct DownloadResponse: Decodable {
  let catch_reports: [CatchReportDTO]
}

struct CatchReportDTO: Decodable, Identifiable {
  let catch_id: String
  let created_at: String
  let latitude: Double?
  let longitude: Double?
  let river: String
  let photo_url: String?
  let notes: String?

  // Catch measurements
  let species: String?
  let sex: String?
  let length_inches: Int?
  let girth_inches: Double?
  let weight_lbs: Double?

  // Convenience
  var id: String { catch_id }
  var createdAt: String { created_at }
  var photoURL: URL? { photo_url.flatMap(URL.init(string:)) }

  /// Display-friendly location: river name first, GPS coordinates if river detection failed,
  /// "Unable to detect via GPS" as last resort.
  var displayLocation: String {
    let lower = river.lowercased()
    guard lower.contains("unable to detect") || lower.contains("unknown") else {
      return river
    }
    if let lat = latitude, let lon = longitude {
      return String(format: "%.4f, %.4f", lat, lon)
    }
    return "-"
  }
}
