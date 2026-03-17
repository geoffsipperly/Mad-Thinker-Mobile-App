// Bend Fly Shop
// AnglerLandingView.swift
// Bend Fly Shop – iOS 15+ nav-bar button + pinned footer

import SwiftUI
import Foundation

// Reads feature flags from Info.plist (populated via xcconfig)
private let FF_CATCH_CAROUSEL: Bool = readFeatureFlag("FF_CATCH_CAROUSEL")
private let FF_THE_BUZZ: Bool = readFeatureFlag("FF_THE_BUZZ")
private let FF_CATCH_MAP: Bool = readFeatureFlag("FF_CATCH_MAP")

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
    return try makeURL(path: downloadCatchPath)
  }
}

// MARK: - Navigation destinations

/// Hashable enum so we can push views onto a `NavigationPath`.
/// Also used by the `navigateTo` environment key for cross-view toolbar navigation.
enum AnglerDestination: Hashable {
  case conditions, learn, community, profile, trip
}

// MARK: - View

struct AnglerLandingView: View {
  @StateObject private var auth = AuthService.shared
  @Environment(\.dismiss) private var dismiss

  // Data state
  @State private var reports: [CatchReportDTO] = []
  @State private var isLoading = false
  @State private var errorText: String?

  // The Buzz state
  @State private var buzzCategory: ForumCategory?
  @State private var buzzThreads: [ForumThread] = []
  @State private var buzzLoading = false

  // Navigation path (enables pop-to-root)
  @State private var navPath = NavigationPath()
  @State private var pendingDestination: AnglerDestination?

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
      if navPath.isEmpty {
        // Already at root — navigate directly
        applyDestination(destination)
      } else {
        // Pop to root first, then navigate after the path settles
        pendingDestination = destination
        navPath = NavigationPath()
      }
    } else {
      // nil = go Home
      pendingDestination = nil
      navPath = NavigationPath()
    }
  }

  private func applyDestination(_ dest: AnglerDestination) {
    switch dest {
    case .trip:
      showTripPrep = true
    case .conditions, .learn, .community, .profile:
      navPath.append(dest)
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
        ToolbarTab(icon: "cloud.sun", label: "Conditions") {
          navPath.append(AnglerDestination.conditions)
        }
        ToolbarTab(icon: "book", label: "Learn") {
          navPath.append(AnglerDestination.learn)
        }
        ToolbarTab(icon: "bubble.left.and.bubble.right", label: "Community") {
          navPath.append(AnglerDestination.community)
        }
      }) {
        content
      }
      .navigationDestination(isPresented: $goToManageAccount) {
        ManageProfileView().environmentObject(auth)
      }
      .navigationDestination(isPresented: $goToCatchMap) {
        AnglerCatchMapView(reports: reports)
      }
      .navigationDestination(for: AnglerDestination.self) { dest in
        switch dest {
        case .conditions:
          FishingForecastRequestView()
            .environment(\.navigateTo, handleNavigateTo)
        case .learn:
          LearnTacticsView()
            .environment(\.navigateTo, handleNavigateTo)
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
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: { goToManageAccount = true }) {
            Image(systemName: "person.circle")
              .font(.title3.weight(.semibold))
              .foregroundColor(.white)
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
    .onChange(of: navPath.count) { newCount in
      // When the path becomes empty and we have a pending destination, navigate there
      if newCount == 0, let dest = pendingDestination {
        pendingDestination = nil
        // Dispatch async so the NavigationStack settles before we push again
        DispatchQueue.main.async {
          applyDestination(dest)
        }
      }
    }
    .task {
      if reports.isEmpty { await fetchReports() }
      await fetchBuzz()
    }
    .onAppear {
      AppLogging.log("[AnglerLandingView] onAppear; authId=\(ObjectIdentifier(auth).hashValue)", level: .debug, category: .auth)
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
      VStack(spacing: 0) {
        // Greeting
        Text("Welcome, \(auth.currentFirstName ?? "Angler")")
          .font(.headline)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.top, 16)

        // Header
        AppHeader(onMapTapped: FF_CATCH_MAP ? {
          goToCatchMap = true
        } : nil)
          .padding(.top, 12)
          .padding(.bottom, 20)

        // Error banner (compact)
        if let err = errorText {
          Text(err)
            .foregroundColor(.red)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }

        // Catch photo carousel
        if FF_CATCH_CAROUSEL {
          if isLoading, sortedReports.isEmpty {
            ProgressView().tint(.white)
              .padding(.vertical, 40)
          } else if sortedReports.isEmpty {
            Text("No catch reports yet.")
              .foregroundColor(.gray)
              .font(.subheadline)
              .padding(.vertical, 14)
          } else {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
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

        // The Buzz — latest forum threads
        if FF_THE_BUZZ, AppEnvironment.shared.buzzCategoryId != nil {
          VStack(alignment: .leading, spacing: 10) {
            Text("The Buzz")
              .font(.title3.weight(.bold))
              .foregroundColor(.blue)

            if let desc = buzzCategory?.description, !desc.isEmpty {
              Text(desc)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(3)
                .padding(.top, -4)
            }

            if buzzLoading {
              ProgressView().tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if buzzThreads.isEmpty {
              Text("No posts yet.")
                .font(.subheadline)
                .foregroundColor(.gray)
            } else {
              ForEach(buzzThreads) { thread in
                NavigationLink(destination: ThreadDetailView(thread: thread, categoryName: "The Buzz").environmentObject(auth)) {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(thread.title)
                      .font(.caption.weight(.semibold))
                      .foregroundColor(.blue)
                      .lineLimit(2)

                    HStack(spacing: 4) {
                      if let first = thread.author_first_name ?? thread.profiles?.first_name {
                        Text(first)
                      } else {
                        Text("Anonymous")
                      }
                      Text("·")
                      if let date = thread.created_at {
                        Text(Self.fmtDate(date))
                      }
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(14)
                  .background(Color.white.opacity(0.06))
                  .clipShape(RoundedRectangle(cornerRadius: 14))
                  .overlay(
                    RoundedRectangle(cornerRadius: 14)
                      .stroke(Color.white.opacity(0.12), lineWidth: 1)
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 20)
        }

        Spacer().frame(height: 16)
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
      // Photo — scaled to fill the card width, clipped to fixed height
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
      .frame(width: 170, height: 170)
      .clipped()

      // River + date below the photo
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(r.river)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(1)
          Text(Self.fmtDate(r.createdAt))
            .font(.caption2)
            .foregroundColor(.gray)
            .lineLimit(1)
        }
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.white.opacity(0.06))
    }
    .frame(width: 170)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
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
