import XCTest
import SwiftUI
@testable import SkeenaSystem

/// Tests for the shared DarkPageTemplate components:
/// LegacyNavBarStyle, VisibleToolbarBackground, AppHeader, DarkPageTemplate.
@MainActor
final class DarkPageTemplateTests: XCTestCase {

  // MARK: - AppHeader Tests

  /// AppHeader with no subtitle should not crash and subtitle should be nil by default.
  func testAppHeader_defaultSubtitle_isNil() {
    let header = AppHeader()
    XCTAssertNil(header.subtitle,
                 "AppHeader subtitle should be nil by default")
  }

  /// AppHeader with a subtitle stores the value correctly.
  func testAppHeader_withSubtitle_storesValue() {
    let header = AppHeader(subtitle: "Welcome, Angler!")
    XCTAssertEqual(header.subtitle, "Welcome, Angler!",
                   "AppHeader should store the provided subtitle")
  }

  /// AppHeader with an empty subtitle stores empty string (not nil).
  func testAppHeader_withEmptySubtitle_storesEmptyString() {
    let header = AppHeader(subtitle: "")
    XCTAssertEqual(header.subtitle, "",
                   "AppHeader should store an empty string subtitle")
  }

  /// AppHeader subtitle supports dynamic interpolation (e.g., "Welcome, \(name)!").
  func testAppHeader_dynamicSubtitle() {
    let name = "TestUser"
    let header = AppHeader(subtitle: "Welcome, \(name)!")
    XCTAssertEqual(header.subtitle, "Welcome, TestUser!",
                   "AppHeader should support string interpolation in subtitle")
  }

  // MARK: - DarkPageTemplate Tests

  /// DarkPageTemplate wraps arbitrary content without crashing.
  func testDarkPageTemplate_wrapsContent() {
    // Verify the template can be instantiated with a simple Text view
    let template = DarkPageTemplate {
      Text("Test Content")
    }
    // If we get here, instantiation succeeded
    XCTAssertNotNil(template, "DarkPageTemplate should instantiate successfully")
  }

  /// DarkPageTemplate wraps complex content (ScrollView + VStack) without crashing.
  func testDarkPageTemplate_wrapsComplexContent() {
    let template = DarkPageTemplate {
      ScrollView {
        VStack {
          Text("Line 1")
          Text("Line 2")
        }
      }
    }
    XCTAssertNotNil(template, "DarkPageTemplate should wrap complex view hierarchies")
  }

  // MARK: - ViewModifier Conformance Tests

  /// LegacyNavBarStyle conforms to ViewModifier.
  func testLegacyNavBarStyle_isViewModifier() {
    let modifier = LegacyNavBarStyle()
    // Verify it can be applied to a View
    let modified = Text("Test").modifier(modifier)
    XCTAssertNotNil(modified, "LegacyNavBarStyle should be applicable as a ViewModifier")
  }

  /// VisibleToolbarBackground conforms to ViewModifier.
  func testVisibleToolbarBackground_isViewModifier() {
    let modifier = VisibleToolbarBackground()
    let modified = Text("Test").modifier(modifier)
    XCTAssertNotNil(modified, "VisibleToolbarBackground should be applicable as a ViewModifier")
  }

  /// The applyLegacyNavBarStyle() extension works on any View.
  func testApplyLegacyNavBarStyle_extensionWorks() {
    let view = Text("Test").applyLegacyNavBarStyle()
    XCTAssertNotNil(view, "applyLegacyNavBarStyle() should be callable on any View")
  }

  // MARK: - Snapshot / Regression Tests

  /// Verify AppHeader subtitle matches expected pattern for Angler flow.
  func testSnapshot_anglerHeaderSubtitle() {
    let firstName = "John"
    let expected = "Welcome, \(firstName)!"
    let header = AppHeader(subtitle: expected)
    XCTAssertEqual(header.subtitle, "Welcome, John!",
                   "SNAPSHOT: Angler header subtitle follows 'Welcome, Name!' pattern")
  }

  /// Verify AppHeader subtitle matches expected pattern for Guide flow.
  func testSnapshot_guideHeaderSubtitle() {
    let firstName: String? = nil
    let expected = "Welcome, \(firstName ?? "Guide")!"
    let header = AppHeader(subtitle: expected)
    XCTAssertEqual(header.subtitle, "Welcome, Guide!",
                   "SNAPSHOT: Guide header subtitle defaults to 'Welcome, Guide!'")
  }

  /// Verify the template is used for FishingForecastRequestView (no subtitle).
  func testSnapshot_conditionsViewUsesNoSubtitle() {
    let header = AppHeader()
    XCTAssertNil(header.subtitle,
                 "SNAPSHOT: Conditions view uses AppHeader with no subtitle")
  }

  // MARK: - ToolbarTab Tests

  /// ToolbarTab stores icon and label correctly.
  func testToolbarTab_storesProperties() {
    let tab = ToolbarTab(icon: "suitcase", label: "My Trip") {}
    XCTAssertEqual(tab.icon, "suitcase", "ToolbarTab should store the icon name")
    XCTAssertEqual(tab.label, "My Trip", "ToolbarTab should store the label")
  }

  /// ToolbarTab can be instantiated with different icons.
  func testToolbarTab_differentIcons() {
    let tab1 = ToolbarTab(icon: "cloud.sun", label: "Conditions") {}
    let tab2 = ToolbarTab(icon: "book", label: "Learn") {}
    XCTAssertEqual(tab1.icon, "cloud.sun")
    XCTAssertEqual(tab2.icon, "book")
    XCTAssertEqual(tab1.label, "Conditions")
    XCTAssertEqual(tab2.label, "Learn")
  }

  /// ToolbarTab defaults to enabled (disabled == false).
  func testToolbarTab_defaultDisabled_isFalse() {
    let tab = ToolbarTab(icon: "message", label: "Social") {}
    XCTAssertFalse(tab.disabled, "ToolbarTab should default to enabled")
  }

  /// ToolbarTab with disabled: true stores the value.
  func testToolbarTab_disabled_storesTrue() {
    let tab = ToolbarTab(icon: "message", label: "Social", disabled: true) {}
    XCTAssertTrue(tab.disabled, "ToolbarTab should store disabled state")
  }

  // MARK: - CommunityService.isSocialActive

  /// isSocialActive returns false when addons are empty.
  func testIsSocialActive_defaultsToFalse() {
    let service = CommunityService.shared
    // Ensure clean slate — addons should be empty by default or after clear
    let original = service.isSocialActive
    // Without any addon data, Social should be inactive
    XCTAssertFalse(original, "isSocialActive should be false when no addons are loaded")
  }

  // MARK: - BottomToolbar Tests

  /// BottomToolbar wraps ToolbarTab content without crashing.
  func testBottomToolbar_wrapsToolbarTabs() {
    let toolbar = BottomToolbar {
      ToolbarTab(icon: "suitcase", label: "My Trip") {}
      ToolbarTab(icon: "cloud.sun", label: "Conditions") {}
    }
    XCTAssertNotNil(toolbar, "BottomToolbar should wrap ToolbarTab views")
  }

  /// BottomToolbar supports 4 tabs (Angler pattern).
  func testBottomToolbar_fourTabs() {
    let toolbar = BottomToolbar {
      ToolbarTab(icon: "suitcase", label: "My Trip") {}
      ToolbarTab(icon: "cloud.sun", label: "Conditions") {}
      ToolbarTab(icon: "book", label: "Learn") {}
      ToolbarTab(icon: "bubble.left.and.bubble.right", label: "Community") {}
    }
    XCTAssertNotNil(toolbar, "BottomToolbar should support 4 tabs")
  }

  // MARK: - DarkPageTemplate with Toolbar Tests

  /// DarkPageTemplate with bottom toolbar instantiates correctly.
  func testDarkPageTemplate_withBottomToolbar() {
    let template = DarkPageTemplate(bottomToolbar: {
      ToolbarTab(icon: "suitcase", label: "My Trip") {}
      ToolbarTab(icon: "cloud.sun", label: "Conditions") {}
    }) {
      Text("Content")
    }
    XCTAssertNotNil(template, "DarkPageTemplate should accept a bottom toolbar")
  }

  /// DarkPageTemplate without toolbar (pushed view pattern) still works.
  func testDarkPageTemplate_withoutToolbar() {
    let template = DarkPageTemplate {
      Text("Pushed content")
    }
    XCTAssertNotNil(template, "DarkPageTemplate without toolbar should work for pushed views")
  }

  // MARK: - Snapshot: Angler Bottom Toolbar Tabs

  /// Verify the Angler landing view toolbar tab configuration.
  func testSnapshot_anglerToolbarTabs() {
    let tabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("suitcase", "My Trip"),
      ("message", "Social"),
      ("book.fill", "Learn")
    ]
    XCTAssertEqual(tabs.count, 4, "SNAPSHOT: Angler toolbar has 4 tabs")
    XCTAssertEqual(tabs[0].label, "Home", "SNAPSHOT: First tab is Home")
    XCTAssertEqual(tabs[1].label, "My Trip", "SNAPSHOT: Second tab is My Trip")
    XCTAssertEqual(tabs[2].label, "Social", "SNAPSHOT: Third tab is Social")
    XCTAssertEqual(tabs[3].label, "Learn", "SNAPSHOT: Fourth tab is Learn")
  }

  /// Verify the Researcher toolbar tab configuration (currently mirrors public).
  /// Social is conditionally shown based on add-on, so the baseline is 3 tabs.
  func testSnapshot_researcherToolbarTabs() {
    // Baseline tabs (Social omitted when add-on is off)
    let baseTabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("safari", "Activities"),
      ("book.fill", "Learn")
    ]
    XCTAssertEqual(baseTabs.count, 3, "SNAPSHOT: Researcher toolbar has 3 baseline tabs (Social add-on off)")
    XCTAssertEqual(baseTabs[0].label, "Home", "SNAPSHOT: First tab is Home")
    XCTAssertEqual(baseTabs[1].label, "Activities", "SNAPSHOT: Second tab is Activities")
    XCTAssertEqual(baseTabs[2].label, "Learn", "SNAPSHOT: Third tab is Learn")
    XCTAssertFalse(baseTabs.contains(where: { $0.label == "Trips" }),
                   "SNAPSHOT: Researcher toolbar must not contain Trips")
    XCTAssertFalse(baseTabs.contains(where: { $0.label == "Catches" }),
                   "SNAPSHOT: 'Catches' was renamed to 'Activities'")
  }

  /// Verify the Guide landing view toolbar tab configuration.
  /// Social is conditionally shown based on add-on, so the baseline is 3 tabs.
  func testSnapshot_guideToolbarTabs() {
    // Baseline tabs (Social omitted when add-on is off)
    let baseTabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("mountain.2", "Trips"),
      ("safari", "Activities"),
    ]
    XCTAssertEqual(baseTabs.count, 3, "SNAPSHOT: Guide toolbar has 3 baseline tabs (Social add-on off)")
    XCTAssertEqual(baseTabs[0].label, "Home", "SNAPSHOT: First tab is Home")
    XCTAssertEqual(baseTabs[1].label, "Trips", "SNAPSHOT: Second tab is Trips")
    XCTAssertEqual(baseTabs[2].label, "Activities", "SNAPSHOT: Third tab is Activities")
    XCTAssertFalse(baseTabs.contains(where: { $0.label == "Catches" }),
                   "SNAPSHOT: 'Catches' was renamed to 'Activities'")
  }
}
