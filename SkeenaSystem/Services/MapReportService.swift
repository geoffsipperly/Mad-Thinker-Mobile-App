// Bend Fly Shop

import Foundation

// MARK: - DTOs

struct MapReportDTO: Decodable, Identifiable {
  var id: String
  let type: String          // "catch" | "active" | "farmed" | "promising" | "passed"
  let date: String
  let latitude: Double?
  let longitude: Double?
  let species: String?
  let lengthInches: Int?
  let memberId: String?
}

struct MapReportsResponse: Decodable {
  let reports: [MapReportDTO]
  let count: Int
}

// MARK: - Service

enum MapReportService {

  static func fetch(communityId: String, memberId: String? = nil) async throws -> [MapReportDTO] {
    let base = AppEnvironment.shared.projectURL
    guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }
    let existingPath = comps.path == "/" ? "" : comps.path
    comps.path = existingPath + "/functions/v1/map-reports"
    let toDate = DateFormatting.iso8601.string(from: Date())
    let fromDate = DateFormatting.iso8601.string(from: Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date())
    var queryItems = [
      URLQueryItem(name: "community_id", value: communityId),
      URLQueryItem(name: "from_date",    value: fromDate),
      URLQueryItem(name: "to_date",      value: toDate),
    ]
    if let memberId {
      queryItems.append(URLQueryItem(name: "member_id", value: memberId))
    }
    comps.queryItems = queryItems
    guard let url = comps.url else { throw URLError(.badURL) }

    AppLogging.log("[MapReports] REQUEST → \(url.absoluteString)", level: .debug, category: .map)

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue(AppEnvironment.shared.anonKey, forHTTPHeaderField: "apikey")

    if let token = await AuthService.shared.currentAccessToken(), !token.isEmpty {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

    AppLogging.log("[MapReports] RESPONSE ← HTTP \(code), \(data.count) bytes", level: .debug, category: .map)

    guard (200..<300).contains(code) else {
      let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      AppLogging.log("[MapReports] ERROR body: \(body)", level: .error, category: .map)
      throw URLError(.badServerResponse)
    }

    let decoded = try JSONDecoder().decode(MapReportsResponse.self, from: data)
    AppLogging.log({ "[MapReports] Decoded \(decoded.count) reports — types: \(decoded.reports.map(\.type).joined(separator: ", "))" }, level: .debug, category: .map)
    for r in decoded.reports {
      AppLogging.log({ "[MapReports]   id=\(r.id) type=\(r.type) lat=\(r.latitude.map { String($0) } ?? "nil") lon=\(r.longitude.map { String($0) } ?? "nil")" }, level: .debug, category: .map)
    }
    return decoded.reports
  }
}
