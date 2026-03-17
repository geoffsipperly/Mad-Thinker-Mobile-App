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

  // Convenience
  var id: String { catch_id }
  var createdAt: String { created_at }
  var photoURL: URL? { photo_url.flatMap(URL.init(string:)) }
}
