// Bend Fly Shop

import Foundation

// MARK: - Response DTOs

struct WeatherSnapshotResponse: Decodable {
  let current: WeatherCurrentDTO
  let hourlyForecast: [WeatherHourlyDTO]
  /// Which backend weather provider was used: "open-meteo" or "weatherapi".
  /// Informational — useful for diagnosing formatting differences between providers.
  let source: String?
}

struct WeatherCurrentDTO: Decodable {
  let temperature: Double
  let weatherCode: Int
  let windSpeed: Double
  let windDirection: Int
  let pressure: Double
}

struct WeatherHourlyDTO: Decodable {
  let time: String
  let temperature: Double
  let weatherCode: Int
  let precipitationProbability: Int
  let pressure: Double
}

// MARK: - Pressure trend

enum WeatherPressureTrend {
  case rising, falling, steady

  var sfSymbol: String {
    switch self {
    case .rising:  return "arrow.up.right"
    case .falling: return "arrow.down.right"
    case .steady:  return "equal"
    }
  }
}

// MARK: - Service

enum WeatherSnapshotService {

  /// Fetch with automatic retry on transient failures (502, timeout).
  /// The `weather-snapshot` edge function can take up to ~10s on cold start
  /// and intermittently returns 502 / hangs, so we apply a per-request
  /// timeout and one automatic retry.
  static func fetch(lat: Double, lon: Double) async throws -> WeatherSnapshotResponse {
    let base = AppEnvironment.shared.projectURL
    AppLogging.log("[Weather] projectURL base=\(base.absoluteString)", level: .debug, category: .network)
    guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      AppLogging.log("[Weather] URLComponents failed for base \(base.absoluteString)", level: .error, category: .network)
      throw URLError(.badURL)
    }
    let existingPath = comps.path == "/" ? "" : comps.path
    comps.path = existingPath + "/functions/v1/weather-snapshot"
    comps.queryItems = nil
    guard let url = comps.url else {
      AppLogging.log("[Weather] URL construction failed from components", level: .error, category: .network)
      throw URLError(.badURL)
    }

    let maxAttempts = 2
    var lastError: Error = URLError(.timedOut)

    for attempt in 1...maxAttempts {
      do {
        let result = try await fetchOnce(url: url, lat: lat, lon: lon, attempt: attempt)
        return result
      } catch {
        lastError = error
        AppLogging.log("[Weather] attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)", level: .error, category: .network)
        if attempt < maxAttempts {
          // Brief delay before retry
          try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
      }
    }
    throw lastError
  }

  private static func fetchOnce(url: URL, lat: Double, lon: Double, attempt: Int) async throws -> WeatherSnapshotResponse {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 15 // seconds — edge function can take ~10s on cold start
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue(AppEnvironment.shared.anonKey, forHTTPHeaderField: "apikey")

    AppLogging.log("[Weather] attempt \(attempt) — requesting token", level: .debug, category: .network)
    if let token = await AuthService.shared.currentAccessToken(), !token.isEmpty {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      AppLogging.log("[Weather] attempt \(attempt) — auth header set, token len=\(token.count)", level: .debug, category: .network)
    } else {
      AppLogging.log("[Weather] attempt \(attempt) — no auth token, sending unauthenticated", level: .debug, category: .network)
    }

    let body: [String: Double] = ["latitude": lat, "longitude": lon]
    req.httpBody = try JSONEncoder().encode(body)

    AppLogging.log("[Weather] attempt \(attempt) — POST \(url.absoluteString)", level: .debug, category: .network)
    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    AppLogging.log("[Weather] attempt \(attempt) — HTTP \(code), \(data.count) bytes", level: .debug, category: .network)
    guard (200..<300).contains(code) else {
      let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
      AppLogging.log("[Weather] attempt \(attempt) — HTTP \(code): \(bodyStr.prefix(500))", level: .error, category: .network)
      throw URLError(.badServerResponse)
    }
    let decoded = try JSONDecoder().decode(WeatherSnapshotResponse.self, from: data)
    AppLogging.log("[Weather] attempt \(attempt) — source: \(decoded.source ?? "unknown")", level: .debug, category: .network)
    return decoded
  }

  // MARK: - Display helpers

  static func conditionText(for code: Int) -> String {
    switch code {
    case 0:       return "Clear"
    case 1:       return "Mainly Clear"
    case 2:       return "Partly Cloudy"
    case 3:       return "Overcast"
    case 45, 48:  return "Foggy"
    case 51...55: return "Drizzle"
    case 61...65: return "Rain"
    case 71...75: return "Snow"
    case 80...82: return "Showers"
    case 95:      return "Thunderstorm"
    default:      return "Mixed"
    }
  }

  static func conditionIcon(for code: Int) -> String {
    switch code {
    case 0, 1:    return "sun.max.fill"
    case 2:       return "cloud.sun.fill"
    case 3:       return "cloud.fill"
    case 45, 48:  return "cloud.fog.fill"
    case 51...55: return "cloud.drizzle.fill"
    case 61...65: return "cloud.rain.fill"
    case 71...75: return "cloud.snow.fill"
    case 80...82: return "cloud.heavyrain.fill"
    case 95:      return "cloud.bolt.fill"
    default:      return "cloud.fill"
    }
  }

  static func windCardinal(from degrees: Int) -> String {
    let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let idx = Int((Double(degrees) / 45.0).rounded()) % 8
    return dirs[idx]
  }

  /// Formats "2026-03-31T14:00" → "2 PM"
  static func hourLabel(from isoDateTime: String) -> String {
    let parts = isoDateTime.split(separator: "T")
    guard parts.count == 2 else { return isoDateTime }
    let timePart = String(parts[1].prefix(5)) // "14:00"
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm"
    if let date = fmt.date(from: timePart) {
      let out = DateFormatter()
      out.dateFormat = "ha" // "2PM"
      return out.string(from: date).lowercased()
    }
    return timePart
  }

  /// Compares current pressure to 3 hours ahead in the forecast to determine trend.
  static func pressureTrend(current: Double, hourly: [WeatherHourlyDTO]) -> WeatherPressureTrend {
    guard hourly.count >= 3 else { return .steady }
    let diff = hourly[2].pressure - current
    if diff > 1.0  { return .rising }
    if diff < -1.0 { return .falling }
    return .steady
  }
}
