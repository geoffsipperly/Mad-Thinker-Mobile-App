// Bend Fly Shop
// DarkPageTemplate.swift — Shared dark-themed page styling components
//
// De-duplicated from AnglerLandingView.swift and LandingView.swift.
// Provides consistent nav-bar appearance, dark background, and a reusable header.

import SwiftUI

// MARK: - User role

/// Distinguishes angler vs guide context so shared views (e.g. Conditions, Community)
/// can render the appropriate toolbar without duplication.
enum AppUserRole { case angler, guide }

private struct UserRoleKey: EnvironmentKey {
  static let defaultValue: AppUserRole = .angler // backward-compatible default
}

extension EnvironmentValues {
  var userRole: AppUserRole {
    get { self[UserRoleKey.self] }
    set { self[UserRoleKey.self] = newValue }
  }
}

// MARK: - Angler navigation environment key

/// Environment key that child views call to navigate.
/// Pass `nil` to pop to root (Home).  Pass a destination to pop-to-root then navigate there.
/// The root NavigationStack owner (AnglerLandingView) sets this closure.
private struct NavigateToKey: EnvironmentKey {
  static let defaultValue: (AnglerDestination?) -> Void = { _ in }
}

extension EnvironmentValues {
  var navigateTo: (AnglerDestination?) -> Void {
    get { self[NavigateToKey.self] }
    set { self[NavigateToKey.self] = newValue }
  }
}

// MARK: - Guide navigation

/// Destinations the guide toolbar can navigate to.
enum GuideDestination: Hashable {
  case trips, catches, community, observations, conditions
}

private struct GuideNavigateToKey: EnvironmentKey {
  static let defaultValue: (GuideDestination?) -> Void = { _ in }
}

extension EnvironmentValues {
  var guideNavigateTo: (GuideDestination?) -> Void {
    get { self[GuideNavigateToKey.self] }
    set { self[GuideNavigateToKey.self] = newValue }
  }
}

// MARK: - Role-aware toolbar

/// A toolbar that renders the correct set of tabs depending on `userRole`.
/// Used by shared views (Conditions, Community) so they don't need role-specific logic.
struct RoleAwareToolbar: View {
  let activeTab: String

  @Environment(\.userRole) private var userRole
  @Environment(\.navigateTo) private var navigateTo
  @Environment(\.guideNavigateTo) private var guideNavigateTo

  var body: some View {
    switch userRole {
    case .angler:
      anglerToolbar
    case .guide:
      guideToolbar
    }
  }

  // MARK: Angler tabs — Home, My Trip, Conditions, Learn, Community
  @ViewBuilder private var anglerToolbar: some View {
    ToolbarTab(icon: "house", label: "Home") {
      navigateTo(nil)
    }
    ToolbarTab(icon: "suitcase", label: "My Trip") {
      navigateTo(.trip)
    }
    ToolbarTab(icon: "cloud.sun", label: "Conditions") {
      if activeTab != "conditions" { navigateTo(.conditions) }
    }
    ToolbarTab(icon: "book", label: "Learn") {
      if activeTab != "learn" { navigateTo(.learn) }
    }
    ToolbarTab(icon: "bubble.left.and.bubble.right", label: "Community") {
      if activeTab != "community" { navigateTo(.community) }
    }
  }

  // MARK: Guide tabs — Home, Trips, Catches, Community, Observations
  @ViewBuilder private var guideToolbar: some View {
    ToolbarTab(icon: "house", label: "Home") {
      guideNavigateTo(nil)
    }
    ToolbarTab(icon: "mountain.2", label: "Trips") {
      if activeTab != "trips" { guideNavigateTo(.trips) }
    }
    ToolbarTab(icon: "camera.viewfinder", label: "Catches") {
      if activeTab != "catches" { guideNavigateTo(.catches) }
    }
    ToolbarTab(icon: "person.3", label: "Community") {
      if activeTab != "community" { guideNavigateTo(.community) }
    }
    ToolbarTab(icon: "waveform", label: "Observations") {
      if activeTab != "observations" { guideNavigateTo(.observations) }
    }
  }
}

// MARK: - UINavigationBar styling for iOS 15

struct LegacyNavBarStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .onAppear {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.tintColor = .white
      }
  }
}

extension View {
  func applyLegacyNavBarStyle() -> some View { modifier(LegacyNavBarStyle()) }
}

// MARK: - iOS 16+ visible toolbar helper

struct VisibleToolbarBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      return AnyView(
        content
          .toolbarBackground(.visible, for: .navigationBar)
          .toolbarBackground(Color.black, for: .navigationBar)
          .toolbarColorScheme(.dark, for: .navigationBar)
      )
    } else {
      return AnyView(content)
    }
  }
}

// MARK: - App Header (logo + title + tagline + optional subtitle)

struct AppHeader: View {
  var subtitle: String? = nil
  var onMapTapped: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 0) {
      Image(AppEnvironment.shared.appLogoAsset)
        .resizable()
        .scaledToFit()
        .frame(width: 160, height: 160)

      ZStack {
        if let onMapTapped {
          HStack {
            Spacer()
            Button(action: onMapTapped) {
              Image(systemName: "map")
                .font(.title3)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
          }
        }
      }
      .padding(.top, 2)

      if let subtitle {
        Text(subtitle)
          .font(.title3.weight(.semibold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .padding(.top, 16)
      }
    }
  }
}

// MARK: - Bottom Toolbar Tab (shared helper)

/// A single tab button used in the pinned bottom toolbar.
/// Provides a consistent icon + label layout across all views.
struct ToolbarTab: View {
  let icon: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 22))
          .foregroundColor(.white.opacity(0.85))
        Text(label)
          .font(.caption2)
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Bottom Toolbar

/// The pinned bottom toolbar with a top border and evenly spaced tab buttons.
/// Pass an array of `ToolbarTab` views or any custom content via `@ViewBuilder`.
///
/// Usage:
/// ```swift
/// BottomToolbar {
///   ToolbarTab(icon: "suitcase", label: "My Trip") { showTrip = true }
///   ToolbarTab(icon: "cloud.sun", label: "Conditions") { goToConditions = true }
/// }
/// ```
struct BottomToolbar<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      // Top border
      Rectangle()
        .fill(Color.white.opacity(0.12))
        .frame(height: 0.5)

      // Toolbar icons
      HStack(spacing: 0) {
        content
      }
      .padding(.top, 8)
      .padding(.bottom, 4)
    }
    .background(Color.black)
  }
}

// MARK: - Dark Page Template

/// A shared page wrapper that provides the consistent dark-themed styling
/// used across Bend Fly Shop views (black background, dark nav bar, white foreground,
/// and an optional pinned bottom toolbar).
///
/// Usage for **pushed** views (no bottom toolbar):
/// ```swift
/// var body: some View {
///   DarkPageTemplate {
///     ScrollView { ... }
///   }
///   .navigationTitle("My Title")
/// }
/// ```
///
/// Usage for **root** views with a bottom toolbar:
/// ```swift
/// var body: some View {
///   DarkPageTemplate(bottomToolbar: {
///     ToolbarTab(icon: "suitcase", label: "My Trip") { ... }
///     ToolbarTab(icon: "cloud.sun", label: "Conditions") { ... }
///   }) {
///     ScrollView { ... }
///   }
/// }
/// ```
struct DarkPageTemplate<Content: View, Toolbar: View>: View {
  let content: Content
  let toolbar: Toolbar?

  /// Creates a template with content and an optional bottom toolbar.
  init(
    @ViewBuilder bottomToolbar: () -> Toolbar,
    @ViewBuilder content: () -> Content
  ) {
    self.toolbar = bottomToolbar()
    self.content = content()
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      content
    }
    .navigationBarTitleDisplayMode(.inline)
    .modifier(VisibleToolbarBackground())
    .applyLegacyNavBarStyle()
    .foregroundColor(.white)
    .preferredColorScheme(.dark)
    .if(toolbar != nil) { view in
      view.safeAreaInset(edge: .bottom) {
        if let toolbar {
          BottomToolbar { toolbar }
        }
      }
    }
  }
}

// No-toolbar convenience initializer
extension DarkPageTemplate where Toolbar == EmptyView {
  /// Creates a template without a bottom toolbar (for pushed views).
  init(@ViewBuilder content: () -> Content) {
    self.toolbar = nil
    self.content = content()
  }
}

// MARK: - Conditional View Modifier Helper

private extension View {
  /// Applies the given transform if the condition is true.
  @ViewBuilder
  func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
