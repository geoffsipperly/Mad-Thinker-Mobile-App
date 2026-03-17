// Bend Fly Shop
// LandingView.swift
// Bend Fly Shop – iOS 15+ nav-bar button + pinned footer
import CoreLocation
import SwiftUI

// MARK: - LandingView

struct LandingView: View {
  @Environment(\.managedObjectContext) private var context
  @StateObject private var auth = AuthService.shared
  @State private var goToAssistant = false
  @State private var showRecordObservation = false

  // Farmed button state
  @StateObject private var locationManager = LocationManager()
  @State private var showFarmedSaved = false
  @State private var showFarmedList = false

  // Path-based nav for guide toolbar navigation
  @State private var navPath = NavigationPath()
  @State private var pendingDestination: GuideDestination?

  // One-time camera/location onboarding for guides
  @AppStorage("hasSeenGuideCameraLocationOnboarding")
  private var hasSeenGuideCameraLocationOnboarding: Bool = false

  @State private var showGuideLocationOnboarding = false

  var body: some View {
    NavigationStack(path: $navPath) {
      DarkPageTemplate(bottomToolbar: {
        RoleAwareToolbar(activeTab: "home")
      }) {
        content
      }
      .navigationDestination(isPresented: $goToAssistant) {
        ReportChatView()
          .navigationBarTitleDisplayMode(.inline)
      }
      .navigationDestination(isPresented: $showFarmedList) {
        FarmedReportsListView()
      }
      .navigationDestination(for: GuideDestination.self) { dest in
        switch dest {
        case .conditions:
          FishingForecastRequestView()
            .environment(\.userRole, .guide)
            .environment(\.guideNavigateTo, handleGuideNavigateTo)
        case .community:
          CommunityForumView()
            .environment(\.userRole, .guide)
            .environment(\.guideNavigateTo, handleGuideNavigateTo)
            .environmentObject(auth)
        case .trips:
          ManageTripsView(guideFirstName: auth.currentFirstName ?? "Guide")
            .environment(\.userRole, .guide)
            .environment(\.guideNavigateTo, handleGuideNavigateTo)
        case .catches:
          ReportsListViewPicMemo()
            .environment(\.userRole, .guide)
            .environment(\.guideNavigateTo, handleGuideNavigateTo)
        case .observations:
          ObservationsListView()
            .environment(\.userRole, .guide)
            .environment(\.guideNavigateTo, handleGuideNavigateTo)
        }
      }
      .onChange(of: navPath.count) { newCount in
        if newCount == 0, let dest = pendingDestination {
          pendingDestination = nil
          DispatchQueue.main.async { applyGuideDestination(dest) }
        }
      }
      .toolbar {
        // Trailing logout
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
      // NEW: one-time camera/location onboarding for guides
      .fullScreenCover(isPresented: $showGuideLocationOnboarding) {
        GuideCameraLocationOnboardingView {
          // Mark as seen and dismiss
          hasSeenGuideCameraLocationOnboarding = true
          showGuideLocationOnboarding = false
        }
      }
      // Record observation sheet
      .fullScreenCover(isPresented: $showRecordObservation) {
        RecordObservationSheet { _ in
          showRecordObservation = false
        }
      }
      // Decide when to show the onboarding
      .onAppear {
        if auth.currentUserType == .guide,
           !hasSeenGuideCameraLocationOnboarding {
          showGuideLocationOnboarding = true
        }
        // Start location updates for farmed button
        locationManager.request()
        locationManager.start()
      }
      // Sync server trips into Core Data so they're available
      // when the guide taps "Record a Catch".
      .task {
        await TripSyncService.shared.syncTripsIfNeeded(context: context)
      }
    }
    .environment(\.userRole, .guide)
    .environment(\.guideNavigateTo, handleGuideNavigateTo)
    .environmentObject(auth)
  }

  // MARK: - Main content

  private var content: some View {
    ScrollView {
      VStack(spacing: 20) {
      AppHeader(subtitle: "Welcome, \(auth.currentFirstName ?? "Guide")!")
        .padding(.top, 20)

      // FEATURE TILES: evenly distributed
      VStack(spacing: 0) {
        // Farmed tile
        Button(action: logFarmedReport) {
          featureTile(
            icon: "leaf.arrow.circlepath",
            title: showFarmedSaved ? "Saved!" : "Farmed",
            subtitle: nil,
            isPrimary: false
          )
        }
        .accessibilityIdentifier("farmedTile")
        .disabled(showFarmedSaved)

        Spacer().frame(height: 12)

        // Record a Catch tile (assistant)
        Button { goToAssistant = true } label: {
          featureTile(
            icon: "ellipsis.bubble",
            title: "Record a catch",
            subtitle: nil,
            isPrimary: false
          )
        }
        .accessibilityIdentifier("myAssistantTile")

        Spacer().frame(height: 12)

        // Get Current Conditions tile
        Button { handleGuideNavigateTo(.conditions) } label: {
          featureTile(
            icon: "cloud.sun.rain",
            title: "Get current conditions",
            subtitle: nil,
            isPrimary: false
          )
        }
        .accessibilityIdentifier("fishingForecastTile")

        Spacer().frame(height: 12)

        // Record observation tile
        Button { showRecordObservation = true } label: {
          featureTile(
            icon: "mic.circle",
            title: "Record observation",
            subtitle: nil,
            isPrimary: false
          )
        }
        .accessibilityIdentifier("recordObservationTile")

      }
      .padding(.horizontal, 16)

      Spacer(minLength: 8)
      }
    }
  }

  // MARK: - Actions

  private func logFarmedReport() {
    let report = FarmedReport(
      id: UUID(),
      createdAt: Date(),
      status: .savedLocally,
      guideName: auth.currentFirstName ?? "Guide",
      lat: locationManager.lastLocation?.coordinate.latitude,
      lon: locationManager.lastLocation?.coordinate.longitude,
      anglerNumber: nil
    )

    FarmedReportStore.shared.add(report)

    // Brief visual confirmation, then reset
    showFarmedSaved = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      showFarmedSaved = false
    }
  }

  private func logoutTapped() {
    Task {
      await auth.signOutRemote()
      await MainActor.run {
        AuthStore.shared.clear()
      }
    }
  }

  // MARK: - Guide Navigation

  /// Centralized handler for guide toolbar navigation.
  /// Pass `nil` to pop to root (Home). Pass a destination to navigate there.
  private func handleGuideNavigateTo(_ destination: GuideDestination?) {
    guard let destination else {
      // Home — pop to root
      pendingDestination = nil
      navPath = NavigationPath()
      return
    }

    if navPath.isEmpty {
      applyGuideDestination(destination)
    } else {
      // Pop to root first, then navigate after stack settles
      pendingDestination = destination
      navPath = NavigationPath()
    }
  }

  private func applyGuideDestination(_ dest: GuideDestination) {
    navPath.append(dest)
  }

  // MARK: - Feature Tile

  private func featureTile(
    icon: String,
    title: String,
    subtitle: String?,
    isPrimary: Bool
  ) -> some View {
    HStack(alignment: .center, spacing: 10) {
      // ICON
      Image(systemName: icon)
        .font(.body.weight(.semibold))
        .foregroundColor(.blue)
        .frame(width: 30, height: 30)
        .padding(6)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))

      // TEXT TO THE RIGHT
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))

        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(
          isPrimary
            ? Color.blue.opacity(0.25)
            : Color.white.opacity(0.04)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.white.opacity(0.10), lineWidth: 1)
    )
    .shadow(
      color: Color.black.opacity(0.35),
      radius: 4,
      x: 0,
      y: 2
    )
  }
}
