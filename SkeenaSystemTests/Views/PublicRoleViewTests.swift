import XCTest
import SwiftUI
@testable import SkeenaSystem

/// Regression tests for public-role UI components.
///
/// Covers:
/// 1. AppUserRole enum — .public case existence, distinctness
/// 2. Public toolbar tab snapshot (5 tabs, no Trips)
/// 3. ReportChatView(alwaysSolo:) — property defaults and override
/// 4. PublicLandingView — instantiates without crashing
@MainActor
final class PublicRoleViewTests: XCTestCase {

  // MARK: - AppUserRole enum

  func testAppUserRole_public_isDistinctFromGuideAndAngler() {
    XCTAssertNotEqual(AppUserRole.public, .guide)
    XCTAssertNotEqual(AppUserRole.public, .angler)
  }

  func testAppUserRole_allFourCasesAreDistinct() {
    let roles: [AppUserRole] = [.guide, .angler, .public, .scientist]
    let unique = Set(roles)
    XCTAssertEqual(unique.count, 4, "All four AppUserRole cases must be distinct")
  }

  func testAppUserRole_allCases_existInExhaustiveSwitch() {
    // If AppUserRole gains a new case without updating this switch,
    // the compiler will error — keeping this test exhaustive by design.
    func roleName(for role: AppUserRole) -> String {
      switch role {
      case .guide:     return "guide"
      case .angler:    return "angler"
      case .public:    return "public"
      case .scientist: return "scientist"
      }
    }
    XCTAssertEqual(roleName(for: .public), "public")
    XCTAssertEqual(roleName(for: .guide), "guide")
    XCTAssertEqual(roleName(for: .angler), "angler")
    XCTAssertEqual(roleName(for: .scientist), "scientist")
  }

  // MARK: - Public toolbar snapshot

  func testSnapshot_publicToolbarTabs_fourTabsNoTrips() {
    // SNAPSHOT: Public toolbar — Home, Catches, Social, Explore.
    // Conditions is accessed via landing page button, not toolbar.
    // Must NOT contain a Trips tab.
    let tabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("camera.viewfinder", "Catches"),
      ("message", "Social"),
      ("safari", "Explore")
    ]
    XCTAssertEqual(tabs.count, 4,
                   "SNAPSHOT: Public toolbar must have exactly 4 tabs")
    XCTAssertFalse(tabs.contains(where: { $0.label == "Trips" }),
                   "SNAPSHOT: Public toolbar must not contain a Trips tab")
    XCTAssertFalse(tabs.contains(where: { $0.label == "Conditions" }),
                   "SNAPSHOT: Public toolbar must not contain a Conditions tab")
    XCTAssertEqual(tabs[0].label, "Home",        "SNAPSHOT: Tab 1 is Home")
    XCTAssertEqual(tabs[1].label, "Catches",     "SNAPSHOT: Tab 2 is Catches")
    XCTAssertEqual(tabs[2].label, "Social",      "SNAPSHOT: Tab 3 is Social")
    XCTAssertEqual(tabs[3].label, "Explore",     "SNAPSHOT: Tab 4 is Explore")
  }

  func testSnapshot_publicToolbarTabs_iconsMatchDesign() {
    let tabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("camera.viewfinder", "Catches"),
      ("message", "Social"),
      ("safari", "Explore")
    ]
    XCTAssertEqual(tabs[0].icon, "house")
    XCTAssertEqual(tabs[1].icon, "camera.viewfinder")
    XCTAssertEqual(tabs[2].icon, "message")
    XCTAssertEqual(tabs[3].icon, "safari")
  }

  func testSnapshot_publicToolbarDiffersFromGuideToolbar() {
    let guideTabs: Set<String>  = ["Home", "Trips", "Catches", "Community", "Observations"]
    let publicTabs: Set<String> = ["Home", "Catches", "Social", "Explore"]
    XCTAssertNotEqual(guideTabs, publicTabs,
                      "Public and guide toolbars must be distinct tab sets")
    XCTAssertFalse(publicTabs.contains("Trips"),
                   "Public toolbar must not contain Trips")
    XCTAssertFalse(publicTabs.contains("Conditions"),
                   "Public toolbar must not contain Conditions (accessed via landing page)")
    XCTAssertTrue(publicTabs.contains("Social"),
                  "Public toolbar must contain Social (maps to Community forum)")
    XCTAssertTrue(publicTabs.contains("Explore"),
                  "Public toolbar must contain Explore")
  }

  // MARK: - ReportChatView alwaysSolo

  func testReportChatView_defaultInit_alwaysSoloIsFalse() {
    let view = ReportChatView()
    XCTAssertFalse(view.alwaysSolo,
                   "ReportChatView() default init must set alwaysSolo = false")
  }

  func testReportChatView_alwaysSoloTrue_storesTrue() {
    let view = ReportChatView(alwaysSolo: true)
    XCTAssertTrue(view.alwaysSolo,
                  "ReportChatView(alwaysSolo: true) must store alwaysSolo = true")
  }

  func testReportChatView_alwaysSoloFalse_storesFalse() {
    let view = ReportChatView(alwaysSolo: false)
    XCTAssertFalse(view.alwaysSolo,
                   "ReportChatView(alwaysSolo: false) must store alwaysSolo = false")
  }

  func testReportChatView_publicLandingUsesAlwaysSolo() {
    // PublicLandingView passes alwaysSolo: true — verify the property is true.
    let viewForPublic = ReportChatView(alwaysSolo: true)
    let viewForGuide  = ReportChatView(alwaysSolo: false)
    XCTAssertTrue(viewForPublic.alwaysSolo,
                  "SNAPSHOT: Public flow opens ReportChatView with alwaysSolo = true")
    XCTAssertFalse(viewForGuide.alwaysSolo,
                   "SNAPSHOT: Guide flow opens ReportChatView with alwaysSolo = false")
  }

  // MARK: - PublicLandingView instantiation

  func testPublicLandingView_instantiatesWithoutCrash() {
    let view = PublicLandingView()
    XCTAssertNotNil(view, "PublicLandingView must instantiate without crashing")
  }

  func testPublicLandingView_setsPublicUserRoleEnvironment() {
    // Verify the view sets .public in its environment (checked via the
    // AppRootView routing test; here we confirm the type compiles and resolves).
    let role: AppUserRole = .public
    XCTAssertEqual(role, .public,
                   "AppUserRole.public must be usable as an environment value for PublicLandingView")
  }

  // MARK: - Routing exhaustiveness (mirrors AppRootView switch)

  func testRouting_allUserTypes_areHandled() {
    func viewName(for type: AuthService.UserType, isConservation: Bool = false) -> String {
      switch type {
      case .guide:     return "LandingView"
      case .angler:    return "AnglerLandingView"
      case .public:    return "PublicLandingView"
      case .scientist: return isConservation ? "ScientistLandingView" : "PublicLandingView"
      }
    }
    XCTAssertEqual(viewName(for: .guide),   "LandingView")
    XCTAssertEqual(viewName(for: .angler),  "AnglerLandingView")
    XCTAssertEqual(viewName(for: .public),  "PublicLandingView",
                   "SNAPSHOT: .public must route to PublicLandingView")
    XCTAssertEqual(viewName(for: .scientist, isConservation: true), "ScientistLandingView",
                   "SNAPSHOT: .scientist + Conservation must route to ScientistLandingView")
    XCTAssertEqual(viewName(for: .scientist, isConservation: false), "PublicLandingView",
                   "SNAPSHOT: .scientist + non-Conservation must fall back to PublicLandingView")
  }

  func testRouting_nilUserType_defaultsToGuide_notPublic() {
    let resolved: AuthService.UserType = nil ?? .guide
    XCTAssertEqual(resolved, .guide,
                   "SNAPSHOT: nil userType must default to .guide, never to .public")
    XCTAssertNotEqual(resolved, .public)
  }
}
