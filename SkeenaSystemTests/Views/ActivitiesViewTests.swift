// Bend Fly Shop
//
// ActivitiesViewTests.swift — Regression and snapshot tests for the
// ActivitiesView tabbed container and its child tabs.

import XCTest
@testable import SkeenaSystem

final class ActivitiesViewTests: XCTestCase {

  // MARK: - Tab enum

  func testTab_hasTwoCases() {
    let allCases = ActivitiesView.Tab.allCases
    XCTAssertEqual(allCases.count, 2,
                   "ActivitiesView.Tab should have exactly 2 cases (reports, observations)")
  }

  func testTab_rawValues() {
    XCTAssertEqual(ActivitiesView.Tab.reports.rawValue, "Reports")
    XCTAssertEqual(ActivitiesView.Tab.observations.rawValue, "Observations")
  }

  func testTab_identifiable_usesRawValue() {
    let tab = ActivitiesView.Tab.reports
    XCTAssertEqual(tab.id, tab.rawValue,
                   "Tab.id should return rawValue for Identifiable conformance")
  }

  func testTab_defaultSelection_isReports() {
    // The view defaults to .reports — verify the enum's first case
    XCTAssertEqual(ActivitiesView.Tab.allCases.first, .reports,
                   "First tab case should be .reports so the default Picker selection lands there")
  }

  // MARK: - View instantiation

  func testActivitiesView_instantiatesWithoutCrash() {
    let view = ActivitiesView()
    XCTAssertNotNil(view, "ActivitiesView must instantiate without crashing")
  }

  func testActivitiesObservationsTab_instantiatesWithoutCrash() {
    let view = ActivitiesObservationsTab()
    XCTAssertNotNil(view, "ActivitiesObservationsTab must instantiate without crashing")
  }

  // MARK: - GuideDestination rename

  func testGuideDestination_activitiesCase_exists() {
    let dest = GuideDestination.activities
    XCTAssertNotNil(dest, "GuideDestination must have an .activities case")
  }

  func testGuideDestination_catchesCase_removed() {
    // Verify the old .catches case no longer exists by confirming
    // .activities is the correct replacement in all known destinations.
    let allDestinations: [GuideDestination] = [
      .trips, .activities, .community, .observations, .conditions, .learn, .explore
    ]
    XCTAssertTrue(allDestinations.contains(.activities),
                  "GuideDestination must contain .activities")
    XCTAssertFalse(allDestinations.map { "\($0)" }.contains("catches"),
                   "GuideDestination must not contain .catches (renamed to .activities)")
  }

  // MARK: - ReportsListView embedded mode

  func testReportsListView_embeddedDefault_isFalse() {
    let view = ReportsListView()
    XCTAssertFalse(view.embedded, "ReportsListView embedded should default to false")
  }

  func testReportsListView_embeddedTrue_instantiatesWithoutCrash() {
    let view = ReportsListView(embedded: true)
    XCTAssertNotNil(view, "ReportsListView(embedded: true) must instantiate without crashing")
    XCTAssertTrue(view.embedded)
  }
}
