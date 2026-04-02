// Bend Fly Shop
// AnglerLandingView.swift
// Bend Fly Shop – iOS 15+ nav-bar button + pinned footer

import CoreLocation
import SwiftUI
import Foundation

// Feature flags are now driven by backend community config (with xcconfig fallback).
// See CommunityConfig.flag(_:) for the resolution chain.

// MARK: - API config (mirrors other files' URL composition)

private enum AnglerLandingAPI {
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

  // Use the variable you specified:
  // DOWNLOAD_CATCH_URL = /functions/v1/download-catch-reports
  private static let downloadCatchPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "DOWNLOAD_CATCH_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/download-catch-reports"
  }()

  private static func logConfig() {
    AppLogging.log("AnglerLanding config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .catch)
    AppLogging.log("AnglerLanding config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .catch)
    AppLogging.log("AnglerLanding config — DOWNLOAD_CATCH_URL: '\(downloadCatchPath)'", level: .debug, category: .catch)
  }

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log(
        "AnglerLanding invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'",
        level: .debug,
        category: .catch
      )
      throw NSError(domain: "AnglerLanding", code: -1000, userInfo: [
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
      throw NSError(domain: "AnglerLanding", code: -1001, userInfo: [
        NSLocalizedDescriptionKey: "Failed to build URL for path: \(path)"
      ])
    }
    return url
  }

  static func downloadCatchURL() throws -> URL {
    logConfig()
    var queryItems: [URLQueryItem] = []
    if let communityId = CommunityService.shared.activeCommunityId {
      queryItems.append(URLQueryItem(name: "community_id", value: communityId))
      AppLogging.log("[AnglerLanding] download scoped to community_id: \(communityId)", level: .debug, category: .catch)
    }
    return try makeURL(path: downloadCatchPath, queryItems: queryItems)
  }
}

// MARK: - Navigation destinations

/// Hashable enum so we can push views onto a `NavigationPath`.
/// Also used by the `navigateTo` environment key for cross-view toolbar navigation.
enum AnglerDestination: Hashable {
  case conditions, learn, community, profile, trip, explore
}

// MARK: - View

struct AnglerLandingView: View {
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared
  @Environment(\.dismiss) private var dismiss

  // Reactive entitlements — driven by backend config with xcconfig fallback
  private var E_CATCH_CAROUSEL: Bool { communityService.activeCommunityConfig.flag("E_CATCH_CAROUSEL") }
  private var E_THE_BUZZ: Bool { communityService.activeCommunityConfig.flag("E_THE_BUZZ") }
  private var E_CATCH_MAP: Bool { communityService.activeCommunityConfig.flag("E_CATCH_MAP") }

  // Data state
  @State private var reports: [CatchReportDTO] = []
  @State private var isLoading = false
  @State private var errorText: String?

  // Map reports (same data source as guide LandingView)
  @State private var mapReports: [MapReportDTO] = []

  // The Buzz state
  @State private var buzzCategory: ForumCategory?
  @State private var buzzThreads: [ForumThread] = []
  @State private var buzzLoading = false

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
  }
  @State private var liveWeather: LiveWeather? = nil

  // Navigation path (enables pop-to-root)
  @State private var navPath = NavigationPath()

  // UI state
  @State private var showTripPrep = false
  @State private var goToManageAccount = false
  @State private var goToCatchMap = false

  // MARK: - Centralized navigation handler
  //
  // Every toolbar tab in every child view calls this closure via
  // `@Environment(\.navigateTo)`.  Passing `nil` = go Home.
  // Passing a destination = pop to root first, then navigate there.

  private func handleNavigateTo(_ destination: AnglerDestination?) {
    if let destination {
      switch destination {
      case .trip:
        // Trip is a slide-over overlay — show it on top of the current view
        // without popping the nav stack to avoid flashing the landing screen.
        showTripPrep = true
      default:
        // Dismiss trip overlay if open
        showTripPrep = false
        // Replace the entire path with the new destination in one step
        // to avoid flashing the landing screen.
        var newPath = NavigationPath()
        newPath.append(destination)
        navPath = newPath
      }
    } else {
      // nil = go Home
      showTripPrep = false
      navPath = NavigationPath()
    }
  }

  var body: some View {
    NavigationStack(path: $navPath) {
      DarkPageTemplate(bottomToolbar: {
        ToolbarTab(icon: "house", label: "Home") {
          // Already on landing — no-op
        }
        ToolbarTab(icon: "suitcase", label: "My Trip") {
          showTripPrep = true
        }
        ToolbarTab(icon: "message", label: "Social") {
          navPath.append(AnglerDestination.community)
        }
        ToolbarTab(icon: "safari", label: "Explore") {
          navPath.append(AnglerDestination.explore)
        }
      }) {
        content
      }
      .navigationDestination(isPresented: $goToManageAccount) {
        ManageProfileView().environmentObject(auth)
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
      .navigationDestination(for: AnglerDestination.self) { dest in
        switch dest {
        case .conditions:
          FishingForecastRequestView()
            .environment(\.navigateTo, handleNavigateTo)
        case .learn:
          LearnTacticsView()
            .environment(\.navigateTo, handleNavigateTo)
            .environmentObject(communityService)
        case .community:
          CommunityForumView()
            .environment(\.navigateTo, handleNavigateTo)
            .environmentObject(auth)
        case .profile:
          ManageProfileView()
            .environmentObject(auth)
        case .trip:
          // Trip is shown as an overlay, not a pushed view — should not appear here
          EmptyView()
        case .explore:
          ExploreView()
            .environment(\.userRole, .angler)
            .environment(\.navigateTo, handleNavigateTo)
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          HStack(spacing: 12) {
            Button(action: { goToManageAccount = true }) {
              Image(systemName: "person.circle")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            }
            CommunitySwitcherChevron()
          }
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
    }
    .environmentObject(auth)
    .task {
      if reports.isEmpty { await fetchReports() }
      await fetchMapReports()
      await fetchBuzz()
    }
    .onAppear {
      locationManager.request()
      locationManager.start()
      AppLogging.log("[AnglerLandingView] onAppear; authId=\(ObjectIdentifier(auth).hashValue)", level: .debug, category: .auth)
    }
    .onChange(of: locationManager.lastLocation) { loc in
      guard liveWeather == nil, let loc else { return }
      Task { await fetchWeather(location: loc) }
    }
    .onDisappear {
      AppLogging.log("[AnglerLandingView] onDisappear", level: .debug, category: .auth)
    }
    // Custom slide-in panel for Trip Prep
    .overlay(
      ZStack(alignment: .trailing) {
        if showTripPrep {
          // Dimmed backdrop
          Color.black.opacity(0.45)
            .ignoresSafeArea()
            .onTapGesture { withAnimation(.easeInOut) { showTripPrep = false } }

          // Right-side panel (needs its own NavigationStack for internal links)
          NavigationStack {
            AnglerTripPrepView(onClose: { withAnimation(.easeInOut) { showTripPrep = false } })
          }
          .environment(\.navigateTo, handleNavigateTo)
          .environmentObject(auth)
          .preferredColorScheme(.dark)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black)
          .transition(.move(edge: .trailing))
        }
      }
    )
    .animation(.easeInOut, value: showTripPrep)
  }

  // MARK: - Main content (no overlay/hit-test traps)

  private var content: some View {
    ScrollView {
      VStack(spacing: 8) {

        // ── Header: name → logo ──────────────────────────────
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
        Button { navPath.append(AnglerDestination.conditions) } label: {
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

  // MARK: - The Buzz

  private func fetchBuzz() async {
    guard let categoryId = AppEnvironment.shared.buzzCategoryId else { return }
    buzzLoading = true
    defer { buzzLoading = false }
    do {
      // Fetch category metadata (for description) and threads concurrently
      async let categoriesTask = ForumAPI.fetchCategories()
      async let threadsTask = ForumAPI.fetchThreads(categoryId: categoryId)

      let categories = try await categoriesTask
      let threads = try await threadsTask

      buzzCategory = categories.first(where: { $0.id == categoryId })
      buzzThreads = Array(threads.prefix(3))
    } catch {
      AppLogging.log("[AnglerLanding] fetchBuzz error: \(error.localizedDescription)", level: .error, category: .forum)
    }
  }

  // MARK: - Networking

  private func fetchReports() async { await fetchReportsInternal(allowRetryOnAuthError: true) }

  private func fetchReportsInternal(allowRetryOnAuthError: Bool) async {
    guard !isLoading else { return }
    errorText = nil
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      AppLogging.log("[AnglerLanding] No access token available", level: .error, category: .catch)
      errorText = "Please sign in to view your catch reports."
      return
    }

    let url: URL
    do {
      url = try AnglerLandingAPI.downloadCatchURL()
    } catch {
      AppLogging.log("[AnglerLanding] Failed to build download URL: \(error.localizedDescription)", level: .error, category: .catch)
      errorText = "Unable to load catch reports. Please try again later."
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    AppLogging.log("AnglerLanding download request URL: \(url.absoluteString)", level: .debug, category: .catch)
    AppLogging.log("AnglerLanding headers — apikey prefix: \(auth.publicAnonKey.prefix(8))…, Accept: application/json", level: .debug, category: .catch)

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      guard (200 ..< 300).contains(code) else {
        if allowRetryOnAuthError, [400, 401, 403].contains(code) {
          _ = await auth.currentAccessToken()
          await fetchReportsInternal(allowRetryOnAuthError: false)
          return
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        AppLogging.log("[AnglerLanding] Catch download failed (\(code)) body: \(body)", level: .error, category: .catch)
        errorText = "Unable to load catch reports. Please try again later."
        return
      }
      let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
      let count = decoded.catch_reports.count
      AppLogging.log("AnglerLanding downloaded catch reports: count=\(count)", level: .debug, category: .catch)
      withAnimation { reports = decoded.catch_reports }
    } catch {
      AppLogging.log("[AnglerLanding] Network error fetching catches: \(error.localizedDescription)", level: .error, category: .catch)
      errorText = "Unable to load catch reports. Please check your connection and try again."
    }
  }

  // MARK: - Map reports

  private func fetchMapReports() async {
    guard let communityId = CommunityService.shared.activeCommunityId else { return }
    do {
      let reports = try await MapReportService.fetch(communityId: communityId)
      await MainActor.run { mapReports = reports }
    } catch {
      AppLogging.log("[AnglerLanding] Map reports fetch failed: \(error.localizedDescription)", level: .error, category: .network)
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
          hourly: slots
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

  // MARK: - Actions

  private func logoutTapped() {
    Task {
      await auth.signOutRemote()
      dismiss()
    }
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
