// Bend Fly Shop

import SwiftUI
import Foundation

private enum AnglerForecastAPI {
  private static let rawBaseURLString: String = {
    (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }()

  private static let baseURLString: String = {
    var s = rawBaseURLString
    if !s.isEmpty, URL(string: s)?.scheme == nil {
      s = "https://" + s
    }
    return s
  }()

  private static let forecastPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "ANGLER_FORECAST_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/angler-forecast"
  }()

  private static func logConfig() {
    AppLogging.log("AnglerForecastAPI config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .angler)
    AppLogging.log("AnglerForecastAPI config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .angler)
    AppLogging.log("AnglerForecastAPI config — ANGLER_FORECAST_URL: '\(forecastPath)'", level: .debug, category: .angler)
  }

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("AnglerForecastAPI invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .debug, category: .angler)
      throw URLError(.badURL)
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    comps.path = normalizedBasePath + normalizedPath

    let existing = base.query != nil ? URLComponents(string: base.absoluteString)?.queryItems ?? [] : []
    comps.queryItems = existing + queryItems

    guard let url = comps.url else { throw URLError(.badURL) }
    return url
  }

  static func forecastURL() throws -> URL {
    logConfig()
    return try makeURL(path: forecastPath)
  }
}

struct AnglerForecastView: View {
  let location: String

  @State private var isLoading = false
  @State private var errorText: String?
  @State private var debugText: String?
  @State private var forecast: AnglerForecastResponse?
  @State private var showFullInterpretation = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      Group {
        if isLoading, forecast == nil {
          VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Fetching forecast…")
              .foregroundColor(.gray)
              .font(.footnote)
          }
        } else if let errorText {
          ScrollView {
            VStack(spacing: 12) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.yellow)
              Text(errorText)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

              if let debugText {
                Text(debugText)
                  .font(.caption)
                  .foregroundColor(.gray)
                  .padding()
                  .background(Color.white.opacity(0.06))
                  .clipShape(RoundedRectangle(cornerRadius: 12))
                  .padding(.horizontal, 16)
              }

              Button("Try Again") { Task { await fetchForecast() } }
                .buttonStyle(.bordered)
            }
            .padding(.top, 24)
          }
        } else if let data = forecast {
          ScrollView {
            VStack(spacing: 16) {
              VStack(spacing: 6) {
                Text(data.location)
                  .font(.title2).bold()
                  .foregroundColor(.white)
                if let gen = AnglerForecastView.formatGeneratedAt(data.generatedAt) {
                  Text("Generated \(gen)")
                    .font(.footnote)
                    .foregroundColor(.gray)
                }
                Text(String(
                  format: "Lat %.4f, Lon %.4f",
                  data.coordinates.latitude,
                  data.coordinates.longitude
                ))
                .font(.caption)
                .foregroundColor(.gray)
              }
              .padding(.vertical, 12)
              .frame(maxWidth: .infinity)
              .background(Color.white.opacity(0.06))
              .clipShape(RoundedRectangle(cornerRadius: 14))
              .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.10), lineWidth: 1))
              .padding(.horizontal, 16)
              .padding(.top, 8)

              if !data.interpretation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                  Text(showFullInterpretation
                    ? data.interpretation
                    : AnglerForecastView.firstWords(of: data.interpretation, count: 75))
                    .foregroundColor(.white.opacity(0.95))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                  Button(action: {
                    withAnimation(.easeInOut) { showFullInterpretation.toggle() }
                  }) {
                    HStack(spacing: 6) {
                      Text(showFullInterpretation ? "See less" : "Show more")
                        .font(.footnote.weight(.semibold))
                        .underline()
                      Image(systemName: showFullInterpretation ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                  }
                  .padding(.top, -2)
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                  .stroke(Color.white.opacity(0.10), lineWidth: 1))
                .padding(.horizontal, 16)
              }

              VStack(spacing: 8) {
                ForEach(data.forecast, id: \.date) { day in
                  ForecastDayRow5Col(day: day)
                }
              }
              .padding(.horizontal, 16)
              .padding(.bottom, 20)
            }
          }
          .overlay(alignment: .topTrailing) {
            if isLoading { ProgressView().tint(.white).padding() }
          }
          .refreshable { await fetchForecast() }
        } else {
          Text("No forecast available.")
            .foregroundColor(.gray)
        }
      }
    }
    .navigationTitle("Extended forecast")
    .navigationBarTitleDisplayMode(.inline)
    .task { if forecast == nil { await fetchForecast() } }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { Task { await fetchForecast() } } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(isLoading)
      }
    }
  }

  // MARK: - Networking

  private func fetchForecast() async {
    guard !isLoading else { return }
    isLoading = true
    errorText = nil
    debugText = nil
    defer { isLoading = false }

    let url: URL
    do {
      url = try AnglerForecastAPI.forecastURL()
    } catch {
      errorText = "Invalid forecast URL (check API_BASE_URL + ANGLER_FORECAST_URL)."
      debugText = "URL build error: \(error.localizedDescription)"
      return
    }

    do {
      var req = URLRequest(url: url)
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.setValue("application/json", forHTTPHeaderField: "Accept")

      let body = ["location": location]
      req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

      AppLogging.log("AnglerForecast POST — URL: \(url.absoluteString)", level: .debug, category: .angler)

      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      let snippet = String(data: data, encoding: .utf8)?.prefix(600) ?? ""
      debugText = "HTTP \(code) • body preview:\n\(snippet)"

      guard (200 ..< 300).contains(code) else {
        if let apiErr = try? JSONDecoder().decode(APIErr.self, from: data) {
          throw ForecastError.api(apiErr.error)
        }
        throw ForecastError.http(code)
      }

      if let maybeErr = try? JSONDecoder().decode(APIErr.self, from: data),
         !maybeErr.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw ForecastError.api(maybeErr.error)
      }

      guard !data.isEmpty else { throw ForecastError.message("Empty response body") }

      let decoded = try JSONDecoder().decode(AnglerForecastResponse.self, from: data)
      withAnimation { self.forecast = decoded }
    } catch let err as ForecastError {
      self.errorText = err.localizedDescription
    } catch {
      self.errorText = "Network/Decode error: \(error.localizedDescription)"
    }
  }

  // MARK: - Helpers

  private static func formatGeneratedAt(_ iso: String) -> String? {
    let isoFmt = ISO8601DateFormatter()
    isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
      let f = DateFormatter()
      f.dateStyle = .medium
      f.timeStyle = .short
      return f.string(from: date)
    }
    return nil
  }

  static func firstWords(of text: String, count: Int) -> String {
    let words = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
    guard words.count > count else { return text }
    return words.prefix(count).joined(separator: " ") + "…"
  }
}

private enum ForecastError: LocalizedError {
  case http(Int)
  case api(String)
  case message(String)

  var errorDescription: String? {
    switch self {
    case let .http(code): "Request failed (\(code))."
    case let .api(msg): msg
    case let .message(m): m
    }
  }
}

private struct ForecastDayRow5Col: View {
  let day: ForecastDay

  var body: some View {
    HStack(spacing: 8) {
      Text(Self.fmtDay(day.date))
        .font(.footnote.weight(.semibold))
        .foregroundColor(.white)
        .frame(width: 90, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      let icon = Self.icon(for: day)
      Image(systemName: icon.name)
        .font(.callout.weight(.bold))
        .foregroundColor(icon.tint)
        .frame(width: 20, height: 20)
        .padding(6)
        .background(icon.tint.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 34, alignment: .leading)

      Text(Self.formatTempPair(max: day.maxTemp, min: day.minTemp))
        .font(.footnote.monospacedDigit())
        .foregroundColor(.white)
        .frame(width: 56, alignment: .trailing)
        .lineLimit(1)

      HStack(spacing: 4) {
        Image(systemName: "drop.fill")
        Text(Self.formatNumber(day.precipitation, suffix: "mm"))
          .monospacedDigit()
      }
      .font(.footnote)
      .foregroundColor(.white.opacity(0.95))
      .frame(width: 60, alignment: .trailing)
      .lineLimit(1)

      HStack(spacing: 4) {
        Image(systemName: "wind")
        Text(Self.formatNumber(day.windSpeed, suffix: "km/h"))
          .monospacedDigit()
      }
      .font(.footnote)
      .foregroundColor(.white.opacity(0.95))
      .frame(width: 72, alignment: .trailing)
      .lineLimit(1)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.10), lineWidth: 1)
    )
  }

  static func icon(for d: ForecastDay) -> (name: String, tint: Color) {
    let p = d.precipitation ?? 0
    switch p {
    case let x where x >= 20: return ("cloud.heavyrain.fill", .blue)
    case 5 ..< 20: return ("cloud.rain.fill", .blue)
    case 1 ..< 5: return ("cloud.sun.rain.fill", .teal)
    default: return ("sun.max.fill", .yellow)
    }
  }

  private static func fmtDay(_ isoDay: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    if let d = f.date(from: isoDay) {
      let out = DateFormatter()
      out.dateFormat = "EEE, MMM d"
      return out.string(from: d)
    }
    return isoDay
  }

  static func formatTempPair(max: Double?, min: Double?) -> String {
    let hi = max.map { String(format: "%.0f°", $0.rounded()) } ?? "–°"
    let lo = min.map { String(format: "%.0f°", $0.rounded()) } ?? "–°"
    return "\(hi)/\(lo)"
  }

  static func formatNumber(_ value: Double?, suffix: String) -> String {
    guard let v = value else { return "–\(suffix)" }
    if v.rounded() == v { return String(format: "%.0f %@", v, suffix) }
    return String(format: "%.1f %@", v, suffix)
  }
}

private struct APIErr: Decodable { let error: String }

struct AnglerForecastResponse: Decodable {
  let location: String
  let coordinates: Coordinates
  let forecastDays: Int
  let forecast: [ForecastDay]
  let interpretation: String
  let generatedAt: String
}

struct Coordinates: Decodable {
  let latitude: Double
  let longitude: Double
}

struct ForecastDay: Decodable {
  let date: String
  let maxTemp: Double?
  let minTemp: Double?
  let precipitation: Double?
  let windSpeed: Double?
  let humidity: Double?
  let pressure: Double?
}
