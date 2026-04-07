// Bend Fly Shop

import CoreLocation
import SwiftUI

// MARK: - API config (mirrors AnglerLandingView's URL composition)

private enum PublicLandingAPI {
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

  private static let downloadCatchPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "DOWNLOAD_CATCH_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/download-catch-reports"
  }()

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      throw NSError(domain: "PublicLanding", code: -1000, userInfo: [
        NSLocalizedDescriptionKey: "Invalid API_BASE_URL (raw: '\(rawBaseURLString)', normalized: '\(baseURLString)')"
      ])
    }
    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port
    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    comps.path = normalizedBasePath + normalizedPath
    let existing = base.query != nil ? (URLComponents(string: base.absoluteString)?.queryItems ?? []) : []
    let merged = existing + queryItems
    comps.queryItems = merged.isEmpty ? nil : merged
    guard let url = comps.url else {
      throw NSError(domain: "PublicLanding", code: -1001, userInfo: [
        NSLocalizedDescriptionKey: "Failed to build URL for path: \(path)"
      ])
    }
    return url
  }

  static func downloadCatchURL() throws -> URL {
    var queryItems: [URLQueryItem] = []
    if let communityId = CommunityService.shared.activeCommunityId {
      queryItems.append(URLQueryItem(name: "community_id", value: communityId))
    }
    return try makeURL(path: downloadCatchPath, queryItems: queryItems)
  }
}

// MARK: - PublicLandingView
//
// Landing screen for users with the "public" community role.
// Identical to GuideLandingView except:
//   - No trip sync on appear (public users have no trip concept)
//   - No trip navigation destination
//   - ReportChatView opened in alwaysSolo mode
//   - userRole environment is .public (toolbar shows no Trips tab)

struct PublicLandingView: View {
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  // Reactive entitlements — driven by backend config with xcconfig fallback
  private var E_CATCH_CAROUSEL: Bool { communityService.activeCommunityConfig.flag("E_CATCH_CAROUSEL") }
  private var E_CATCH_MAP: Bool { communityService.activeCommunityConfig.flag("E_CATCH_MAP") }

  @State private var goToAssistant = false
  @State private var showRecordActivity = false

  // Catch report data
  @State private var reports: [CatchReportDTO] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var goToCatchMap = false

  // Map reports (same data source as GuideLandingView)
  @State private var mapReports: [MapReportDTO] = []

  // Location (for weather)
  @StateObject private var locationManager = LocationManager()

  // Live weather
  private struct LiveWeather {
    let locationName: String
    let condition: String
    let icon: String
    let temp: Int
    let windDir: String
    let windSpeed: Int
    let pressureVal: Int
    let pressureTrend: WeatherPressureTrend
    struct HourlySlot: Identifiable {
      var id: String { hour }
      let hour: String
      let icon: String
      let temp: Int
      let precipChance: Int
    }
    let hourly: [HourlySlot]
    /// Backend weather provider: "open-meteo" or "weatherapi". Informational.
    let source: String?
  }
  @State private var liveWeather: LiveWeather? = nil

  // Path-based nav for toolbar navigation
  @State private var navPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navPath) {
      DarkPageTemplate(bottomToolbar: {
        RoleAwareToolbar(activeTab: "home")
      }) {
        content
      }
      .navigationDestination(isPresented: $goToAssistant) {
        ReportChatView(alwaysSolo: true, directToChat: true, onSaved: {
          goToAssistant = false
        })
          .navigationBarTitleDisplayMode(.inline)
      }
      .navigationDestination(isPresented: $showRecordActivity) {
        RecordActivityView()
          .environment(\.userRole, .public)
          .environment(\.guideNavigateTo, handleNavigateTo)
          .environmentObject(auth)
      }
      .navigationDestination(isPresented: $goToCatchMap) {
        DarkPageTemplate {
          VStack(spacing: 4) {
            GuideLandingMapView(reports: mapReports)
              .ignoresSafeArea(edges: .bottom)
            GuideLandingMapLegend()
              .padding(.bottom, 8)
          }
        }
        .navigationTitle("Catch Map")
      }
      .navigationDestination(for: GuideDestination.self) { dest in
        switch dest {
        case .conditions:
          FishingForecastRequestView()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .community:
          SocialFeedView()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .catches:
          ReportsListViewPicMemo()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .observations:
          ObservationsListView()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .trips:
          // Public users have no trips — should never be reached
          EmptyView()
        case .learn:
          LearnTacticsView()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
            .environmentObject(communityService)
        case .explore:
          ExploreView()
            .environment(\.userRole, .public)
            .environment(\.guideNavigateTo, handleNavigateTo)
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          CommunityToolbarButton()
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: logoutTapped) {
            HStack(spacing: 6) {
              Image(systemName: "person.crop.circle.badge.xmark")
                .font(.title3.weight(.semibold))
              Text("Log out")
                .font(.footnote.weight(.semibold))
            }
          }
          .accessibilityIdentifier("logoutCapsule")
        }
      }
      .onAppear {
        locationManager.request()
        locationManager.start()
        Task {
          await fetchReports()
          await fetchMapReports()
        }
      }
      .onChange(of: locationManager.lastLocation) { loc in
        guard liveWeather == nil, let loc else { return }
        Task { await fetchWeather(location: loc) }
      }
    }
    .environment(\.userRole, .public)
    .environment(\.guideNavigateTo, handleNavigateTo)
    .environmentObject(auth)
  }

  // MARK: - Main content

  private var content: some View {
    ScrollView {
      VStack(spacing: 8) {

        // ── Header: name → logo → record ──────────────────────────────
        VStack(spacing: 0) {
          // User name — left aligned
          Text("\(auth.currentFirstName ?? "") \(auth.currentLastName ?? "")")
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

          // Community logo — centred
          CommunityLogoView(config: communityService.activeCommunityConfig, size: 160)
            .frame(maxWidth: .infinity)

          // Record capsule — right aligned, directly below logo
          Button { showRecordActivity = true } label: {
            Text("Record")
              .font(.caption.weight(.bold))
              .foregroundColor(.white)
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(Color.blue, in: Capsule())
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.horizontal, 20)
          .padding(.top, 4)
          .accessibilityIdentifier("recordActivityButton")
        }
        .padding(.top, 12)

        // ── Weather tile ───────────────────────────────────────────────
        VStack(spacing: 0) {
          // Current conditions row: location | temp | wind | pressure
          HStack(spacing: 0) {
            Text(liveWeather?.locationName ?? "\u{2013}")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(.white)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
              Image(systemName: liveWeather?.icon ?? "thermometer")
                .font(.caption)
                .foregroundColor(weatherIconColor(liveWeather?.icon))
              Text(liveWeather.map { "\(communityService.activeCommunityConfig.temperature(Double($0.temp)))\(communityService.activeCommunityConfig.tempUnit)" } ?? "\u{2013}")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
            }
            .frame(width: 56, alignment: .center)

            HStack(spacing: 3) {
              Image(systemName: "wind")
                .font(.caption2)
                .foregroundColor(.gray)
              Text(liveWeather.map { "\($0.windDir) \(communityService.activeCommunityConfig.windSpeed(Double($0.windSpeed)))" } ?? "\u{2013}")
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
            }
            .frame(width: 56, alignment: .center)

            HStack(spacing: 3) {
              Image(systemName: "barometer")
                .font(.caption2)
                .foregroundColor(.gray)
              Text(liveWeather.map { "\($0.pressureVal)" } ?? "\u{2013}")
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
              Image(systemName: liveWeather?.pressureTrend.sfSymbol ?? "minus")
                .font(.system(size: 8))
                .foregroundColor(pressureTrendColor(liveWeather?.pressureTrend))
            }
            .frame(width: 64, alignment: .center)
          }
          .padding(.horizontal, 14)
          .padding(.top, 8)
          .padding(.bottom, 6)

          // Hourly strip
          if let hourly = liveWeather?.hourly, !hourly.isEmpty {
            Rectangle()
              .fill(Color.white.opacity(0.12))
              .frame(height: 0.5)
              .padding(.horizontal, 14)

            HStack(spacing: 0) {
              ForEach(hourly) { slot in
                VStack(alignment: .center, spacing: 2) {
                  Text(slot.hour)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                  Image(systemName: slot.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(weatherIconColor(slot.icon))
                  Text("\(communityService.activeCommunityConfig.temperature(Double(slot.temp)))\u{00B0}")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                  Text(slot.precipChance > 0 ? "\(slot.precipChance)%" : " ")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity)
              }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
          }
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)

        // ── Fisheries Conditions ───────────────────────────────────────
        Button { handleNavigateTo(.conditions) } label: {
          HStack(spacing: 8) {
            Image(systemName: "water.waves")
              .font(.caption)
              .foregroundColor(.white)
            Text("Fisheries Conditions")
              .font(.caption.weight(.semibold))
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundColor(.white.opacity(0.4))
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityIdentifier("fishingForecastTile")

        // Section divider
        Rectangle()
          .fill(Color.white.opacity(0.12))
          .frame(height: 0.5)
          .padding(.vertical, 2)

        // Catch photo carousel
        if E_CATCH_CAROUSEL {
          VStack(alignment: .leading, spacing: 8) {
            // Header row — "Your recent activity" + map icon
            HStack(alignment: .center) {
              Text("Your recent activity")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
              Spacer()
              if E_CATCH_MAP {
                Button { goToCatchMap = true } label: {
                  Image(systemName: "map")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 16)

            if isLoading, sortedReports.isEmpty {
              ProgressView().tint(.white)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            } else if sortedReports.isEmpty {
              Text("No catch reports yet.")
                .foregroundColor(.gray)
                .font(.subheadline)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            } else {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                  ForEach(sortedReports) { r in
                    NavigationLink(destination: CatchDetailView(report: r).environmentObject(auth)) {
                      catchCard(r)
                    }
                    .buttonStyle(.plain)
                  }
                }
                .padding(.horizontal, 16)
              }
            }
          }
        }

        // Error banner
        if let err = errorText {
          Text(err)
            .foregroundColor(.red)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }

        Spacer(minLength: 8)
      }
    }
  }

  // MARK: - Derived data

  private var sortedReports: [CatchReportDTO] {
    reports.sorted {
      let d0 = Self.parseISO($0.createdAt) ?? .distantPast
      let d1 = Self.parseISO($1.createdAt) ?? .distantPast
      return d0 > d1
    }
  }

  // MARK: - Catch card (carousel)

  @ViewBuilder
  private func catchCard(_ r: CatchReportDTO) -> some View {
    VStack(spacing: 0) {
      AsyncImage(url: r.photoURL) { phase in
        switch phase {
        case .empty:
          ZStack { Color.white.opacity(0.08); ProgressView().tint(.white) }
        case let .success(img):
          img.resizable().scaledToFill()
        case .failure:
          ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "photo")
              .font(.largeTitle)
              .foregroundColor(.white.opacity(0.3))
          }
        @unknown default:
          Color.white.opacity(0.08)
        }
      }
      .frame(width: 140, height: 140)
      .clipped()

      HStack {
        VStack(alignment: .leading, spacing: 1) {
          Text(r.displayLocation)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(1)
          Text(Self.fmtDate(r.createdAt))
            .font(.caption2)
            .foregroundColor(.gray)
            .lineLimit(1)
        }
        Spacer()
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.white.opacity(0.06))
    }
    .frame(width: 140)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  // MARK: - Networking

  private func fetchReports() async { await fetchReportsInternal(allowRetryOnAuthError: true) }

  private func fetchReportsInternal(allowRetryOnAuthError: Bool) async {
    guard !isLoading else { return }
    errorText = nil
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      errorText = "Please sign in to view your catch reports."
      return
    }

    let url: URL
    do {
      url = try PublicLandingAPI.downloadCatchURL()
    } catch {
      AppLogging.log("[PublicLanding] Failed to build download URL: \(error.localizedDescription)", level: .error, category: .catch)
      errorText = "Unable to load catch reports. Please try again later."
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      guard (200 ..< 300).contains(code) else {
        if allowRetryOnAuthError, [400, 401, 403].contains(code) {
          _ = await auth.currentAccessToken()
          await fetchReportsInternal(allowRetryOnAuthError: false)
          return
        }
        errorText = "Unable to load catch reports. Please try again later."
        return
      }
      let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
      withAnimation { reports = decoded.catch_reports }
    } catch {
      AppLogging.log("[PublicLanding] Network error fetching catches: \(error.localizedDescription)", level: .error, category: .catch)
      errorText = "Unable to load catch reports. Please check your connection and try again."
    }
  }

  // MARK: - Map reports

  private func fetchMapReports() async {
    guard let communityId = CommunityService.shared.activeCommunityId else { return }
    do {
      let reports = try await MapReportService.fetch(communityId: communityId, memberId: auth.currentMemberId)
      await MainActor.run { mapReports = reports }
    } catch {
      AppLogging.log("[PublicLanding] Map reports fetch failed: \(error.localizedDescription)", level: .error, category: .network)
    }
  }

  // MARK: - Weather

  private func fetchWeather(location: CLLocation) async {
    let lat = location.coordinate.latitude
    let lon = location.coordinate.longitude

    // Reverse geocode for city name
    let geocoder = CLGeocoder()
    let locationName: String
    if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
      let city = placemark.locality
        ?? placemark.subLocality
        ?? placemark.subAdministrativeArea
        ?? ""
      let state = placemark.administrativeArea ?? ""
      locationName = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    } else {
      locationName = ""
    }

    do {
      let response = try await WeatherSnapshotService.fetch(lat: lat, lon: lon)
      let w = response.current
      let slots = response.hourlyForecast.map { h in
        LiveWeather.HourlySlot(
          hour: WeatherSnapshotService.hourLabel(from: h.time),
          icon: WeatherSnapshotService.conditionIcon(for: h.weatherCode),
          temp: Int(h.temperature.rounded()),
          precipChance: h.precipitationProbability
        )
      }
      await MainActor.run {
        liveWeather = LiveWeather(
          locationName: locationName,
          condition: WeatherSnapshotService.conditionText(for: w.weatherCode),
          icon: WeatherSnapshotService.conditionIcon(for: w.weatherCode),
          temp: Int(w.temperature.rounded()),
          windDir: WeatherSnapshotService.windCardinal(from: w.windDirection),
          windSpeed: Int(w.windSpeed.rounded()),
          pressureVal: Int(w.pressure.rounded()),
          pressureTrend: WeatherSnapshotService.pressureTrend(current: w.pressure, hourly: response.hourlyForecast),
          hourly: slots,
          source: response.source
        )
      }
    } catch {
      AppLogging.log("[Weather] Fetch failed: \(error.localizedDescription)", level: .error, category: .network)
    }
  }

  private func pressureTrendColor(_ trend: WeatherPressureTrend?) -> Color {
    switch trend {
    case .rising:  return .green
    case .falling: return .red
    default:       return .gray
    }
  }

  private func weatherIconColor(_ icon: String?) -> Color {
    guard let icon else { return .gray }
    if icon.contains("sun") { return .yellow }
    if icon.contains("snow") { return .cyan }
    if icon.contains("bolt") { return .yellow }
    return .gray
  }

  private func logoutTapped() {
    Task {
      await auth.signOutRemote()
      await MainActor.run {
        AuthStore.shared.clear()
      }
    }
  }

  // MARK: - Navigation

  private func handleNavigateTo(_ destination: GuideDestination?) {
    guard let destination else {
      navPath = NavigationPath()
      return
    }
    var newPath = NavigationPath()
    newPath.append(destination)
    navPath = newPath
  }

  // MARK: - Helpers

  private static func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }

  private static func fmtDate(_ iso: String) -> String {
    if let d = parseISO(iso) {
      let f = DateFormatter()
      f.dateStyle = .medium; f.timeStyle = .short
      return f.string(from: d)
    }
    return iso
  }
}
