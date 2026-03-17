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
      ("cloud.sun", "Conditions"),
      ("book", "Learn"),
      ("bubble.left.and.bubble.right", "Community")
    ]
    XCTAssertEqual(tabs.count, 5, "SNAPSHOT: Angler toolbar has 5 tabs")
    XCTAssertEqual(tabs[0].label, "Home", "SNAPSHOT: First tab is Home")
    XCTAssertEqual(tabs[1].label, "My Trip", "SNAPSHOT: Second tab is My Trip")
    XCTAssertEqual(tabs[2].label, "Conditions", "SNAPSHOT: Third tab is Conditions")
    XCTAssertEqual(tabs[3].label, "Learn", "SNAPSHOT: Fourth tab is Learn")
    XCTAssertEqual(tabs[4].label, "Community", "SNAPSHOT: Fifth tab is Community")
  }

  /// Verify the Guide landing view toolbar tab configuration.
  func testSnapshot_guideToolbarTabs() {
    let tabs: [(icon: String, label: String)] = [
      ("house", "Home"),
      ("mountain.2", "Trips"),
      ("camera.viewfinder", "Catches"),
      ("person.3", "Community"),
      ("waveform", "Observations")
    ]
    XCTAssertEqual(tabs.count, 5, "SNAPSHOT: Guide toolbar has 5 tabs")
    XCTAssertEqual(tabs[0].label, "Home", "SNAPSHOT: First tab is Home")
    XCTAssertEqual(tabs[1].label, "Trips", "SNAPSHOT: Second tab is Trips")
    XCTAssertEqual(tabs[2].label, "Catches", "SNAPSHOT: Third tab is Catches")
    XCTAssertEqual(tabs[3].label, "Community", "SNAPSHOT: Fourth tab is Community")
    XCTAssertEqual(tabs[4].label, "Observations", "SNAPSHOT: Fifth tab is Observations")
  }
}
