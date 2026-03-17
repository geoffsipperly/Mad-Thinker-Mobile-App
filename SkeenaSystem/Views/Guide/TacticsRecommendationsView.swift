// Bend Fly Shop

import SwiftUI

// MARK: - API Models

struct TacticsResponse: Decodable {
  let summary: String
  let detailedAnalysis: String
  let recommendedFlies: [String]
  let optimalTimes: String
  let waterApproach: String

  enum CodingKeys: String, CodingKey {
    case summary
    case detailedAnalysis = "detailed_analysis"
    case recommendedFlies = "recommended_flies"
    case optimalTimes = "optimal_times"
    case waterApproach = "water_approach"
  }
}

struct TacticsErrorResponse: Decodable {
  let error: String
}

// MARK: - View

struct TacticsRecommendationsView: View {
  let date: String
  let river: String

  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var tactics: TacticsResponse?

  // Compose endpoint from API_BASE_URL (base) + TACTICS_RECOMMENDATIONS_URL (path)
  private static let rawBaseURLString = APIURLUtilities.infoPlistString(forKey: "API_BASE_URL")
  private static let baseURLString = APIURLUtilities.normalizeBaseURL(rawBaseURLString)
  private static let rawTacticsPath = APIURLUtilities.infoPlistString(forKey: "TACTICS_RECOMMENDATIONS_URL")

  private static func logConfig() {
    AppLogging.log("[Tactics] config — API_BASE_URL (raw): '" + rawBaseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("[Tactics] config — API_BASE_URL (normalized): '" + baseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("[Tactics] config — TACTICS_RECOMMENDATIONS_URL (path): '" + rawTacticsPath + "'", level: .debug, category: .trip)
  }

  private static func makeURL() throws -> URL {
    // If TACTICS_RECOMMENDATIONS_URL is a full URL (scheme + host), use it directly
    if let maybeURL = URL(string: rawTacticsPath),
       let uScheme = maybeURL.scheme, !uScheme.isEmpty,
       let uHost = maybeURL.host, !uHost.isEmpty {
      AppLogging.log("[Tactics] Using full TACTICS_RECOMMENDATIONS_URL: \(maybeURL.absoluteString)", level: .debug, category: .trip)
      return maybeURL
    }

    // If it has a scheme but no host (e.g., 'https:'), it's invalid
    if let maybeURL = URL(string: rawTacticsPath),
       let uScheme = maybeURL.scheme, !uScheme.isEmpty,
       maybeURL.host == nil || maybeURL.host?.isEmpty == true {
      AppLogging.log("[Tactics] Invalid TACTICS_RECOMMENDATIONS_URL (scheme present, host missing): '\(rawTacticsPath)'", level: .error, category: .trip)
      throw NSError(domain: "Tactics", code: -1002, userInfo: [NSLocalizedDescriptionKey: "Invalid TACTICS_RECOMMENDATIONS_URL ('\(rawTacticsPath)') — scheme present but host missing"])
    }

    // Otherwise, compose with API_BASE_URL. If path is explicitly relative (starts with '/'), keep it as-is.
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("[Tactics] invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .error, category: .trip)
      throw NSError(domain: "Tactics", code: -1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API_BASE_URL ('\(rawBaseURLString)')"])
    }

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath: String = {
      let p = rawTacticsPath.trimmingCharacters(in: .whitespacesAndNewlines)
      if p.isEmpty { return "" }
      return p.hasPrefix("/") ? p : "/" + p
    }()

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port
    comps.path = normalizedBasePath + normalizedPath

    let existing = base.query != nil ? URLComponents(string: base.absoluteString)?.queryItems ?? [] : []
    comps.queryItems = existing

    guard let url = comps.url else {
      throw NSError(domain: "Tactics", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Failed to build tactics URL from base + path ('\(rawTacticsPath)')"])
    }
    return url
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      content
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }
    .navigationTitle("Today’s tactics")
    .navigationBarTitleDisplayMode(.inline)
    .preferredColorScheme(.dark)
    .onAppear {
      if tactics == nil {
        fetchTactics()
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      VStack {
        Spacer()
        ProgressView()
          .progressViewStyle(.circular)
          .tint(.blue)
        Text("Analyzing conditions…")
          .font(.footnote)
          .foregroundColor(.white.opacity(0.7))
        Spacer()
      }

    } else if let errorMessage {
      VStack {
        Spacer()
        Text("Unable to load tactics.")
          .font(.subheadline).bold()
          .foregroundColor(.white)

        Text(errorMessage)
          .font(.footnote)
          .foregroundColor(.red.opacity(0.8))
          .multilineTextAlignment(.center)
          .padding(.top, 4)

        Button {
          isLoading = true
          self.errorMessage = nil
          fetchTactics()
        } label: {
          Text("Retry")
            .font(.footnote).bold()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.blue.opacity(0.9)))
            .foregroundColor(.white)
        }
        .padding(.top, 10)
        Spacer()
      }

    } else if let tactics {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          // SUMMARY
          sectionCard(title: "Summary", body: tactics.summary)

          // OPTIMAL TIMES
          sectionCard(title: "Optimal Times", body: tactics.optimalTimes)

          // WATER APPROACH
          sectionCard(title: "Water Approach", body: tactics.waterApproach)

          // RECOMMENDED FLIES
          if !tactics.recommendedFlies.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Recommended Flies")
                .font(.subheadline).bold()
                .foregroundColor(.blue)

              ForEach(tactics.recommendedFlies, id: \.self) { fly in
                HStack(spacing: 8) {
                  Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                  Text(fly)
                    .font(.footnote)
                    .foregroundColor(.white)
                }
              }
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }

          // DETAILED ANALYSIS
          sectionCard(title: "Detailed Analysis", body: tactics.detailedAnalysis)
        }
      }
    } else {
      EmptyView()
    }
  }

  // MARK: - Section Card Builder

  private func sectionCard(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline).bold()
        .foregroundColor(.blue)

      Text(body)
        .font(.footnote)
        .foregroundColor(.white)
    }
    .padding(10)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Networking

  private func fetchTactics() {
    do {
      Self.logConfig()
      let url = try Self.makeURL()
      AppLogging.log("[Tactics] POST request URL: \(url.absoluteString)", level: .debug, category: .trip)
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body: [String: String] = [
        "date": date,
        "river": river
      ]

      do {
        request.httpBody = try JSONEncoder().encode(body)
      } catch {
        self.isLoading = false
        self.errorMessage = "Failed to encode request."
        return
      }

      URLSession.shared.dataTask(with: request) { data, _, error in
        DispatchQueue.main.async {
          self.isLoading = false

          if let error {
            self.errorMessage = error.localizedDescription
            return
          }

          guard let data else {
            self.errorMessage = "Empty response from server."
            return
          }

          if let tactics = try? JSONDecoder().decode(TacticsResponse.self, from: data) {
            self.tactics = tactics
            return
          }

          if let apiError = try? JSONDecoder().decode(TacticsErrorResponse.self, from: data) {
            self.errorMessage = apiError.error
            return
          }

          self.errorMessage = "Unexpected response from server."
        }
      }.resume()
    } catch {
      self.isLoading = false
      self.errorMessage = error.localizedDescription
    }
  }
}
