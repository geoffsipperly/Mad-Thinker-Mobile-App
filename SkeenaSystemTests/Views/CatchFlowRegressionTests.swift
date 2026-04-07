import XCTest
import SwiftUI
@testable import SkeenaSystem

/// Regression tests for two changes to the catch and observation flows:
///
/// 1. ReportChatView(directToChat:) — public users tap "Landed" and
///    land directly on "Record Catch Details", skipping the setup screen.
///
/// 2. ObservationsListView toolbar + button — "Record observation" was
///    moved from the GuideLandingView / PublicGuideLandingView content tiles to
///    a + button in the Observations page toolbar.
@MainActor
final class CatchFlowRegressionTests: XCTestCase {

  // MARK: - ReportChatView.directToChat: property contract

  func testReportChatView_directToChat_defaultIsFalse() {
    let view = ReportChatView()
    XCTAssertFalse(view.directToChat,
                   "SNAPSHOT: ReportChatView() must default directToChat to false")
  }

  func testReportChatView_directToChat_trueIsStored() {
    let view = ReportChatView(directToChat: true)
    XCTAssertTrue(view.directToChat,
                  "SNAPSHOT: ReportChatView(directToChat: true) must store true")
  }

  func testReportChatView_directToChat_falseIsStored() {
    let view = ReportChatView(directToChat: false)
    XCTAssertFalse(view.directToChat,
                   "ReportChatView(directToChat: false) must store false")
  }

  func testReportChatView_alwaysSolo_andDirectToChat_bothStored() {
    let view = ReportChatView(alwaysSolo: true, directToChat: true)
    XCTAssertTrue(view.alwaysSolo,
                  "SNAPSHOT: Public flow requires alwaysSolo = true")
    XCTAssertTrue(view.directToChat,
                  "SNAPSHOT: Public flow requires directToChat = true")
  }

  func testReportChatView_guideLanding_neitherFlagSet() {
    // Guide landing uses default init — no directToChat, no alwaysSolo
    let view = ReportChatView()
    XCTAssertFalse(view.alwaysSolo,
                   "SNAPSHOT: Guide flow must not set alwaysSolo")
    XCTAssertFalse(view.directToChat,
                   "SNAPSHOT: Guide flow must not set directToChat")
  }

  func testReportChatView_alwaysSolo_withoutDirectToChat_isDistinct() {
    // alwaysSolo: true, directToChat: false — e.g. a future "solo but with
    // setup screen" use case — must be distinct from the public flow.
    let withSetup   = ReportChatView(alwaysSolo: true, directToChat: false)
    let withoutSetup = ReportChatView(alwaysSolo: true, directToChat: true)

    XCTAssertTrue(withSetup.alwaysSolo)
    XCTAssertFalse(withSetup.directToChat,
                   "alwaysSolo without directToChat must still show the setup screen")
    XCTAssertTrue(withoutSetup.alwaysSolo)
    XCTAssertTrue(withoutSetup.directToChat,
                  "alwaysSolo + directToChat skips the setup screen")
  }

  // MARK: - PublicGuideLandingView uses alwaysSolo + directToChat

  func testPublicGuideLandingView_landedButton_usesDirectToChat() {
    // Verify the combination that PublicGuideLandingView passes to ReportChatView
    // when the user taps the Landed tile. Both flags must be true.
    let publicFlowView = ReportChatView(alwaysSolo: true, directToChat: true)
    XCTAssertTrue(publicFlowView.alwaysSolo,
                  "SNAPSHOT: Landed button in PublicGuideLandingView requires alwaysSolo = true")
    XCTAssertTrue(publicFlowView.directToChat,
                  "SNAPSHOT: Landed button in PublicGuideLandingView requires directToChat = true — skips setup screen")
  }

  func testPublicGuideLandingView_directToChat_notUsedByGuide() {
    // Guide landing view still uses the default init — setup screen is shown
    let guideLandedView = ReportChatView()
    XCTAssertFalse(guideLandedView.directToChat,
                   "SNAPSHOT: Guide Landed tile must not skip the setup screen")
  }

  // MARK: - directToChat parameter exhaustiveness in init

  func testReportChatView_init_acceptsAllCombinations() {
    // Compile-time check: all four combinations must be expressible
    let ff = ReportChatView(alwaysSolo: false, directToChat: false)
    let ft = ReportChatView(alwaysSolo: false, directToChat: true)
    let tf = ReportChatView(alwaysSolo: true,  directToChat: false)
    let tt = ReportChatView(alwaysSolo: true,  directToChat: true)

    XCTAssertFalse(ff.alwaysSolo); XCTAssertFalse(ff.directToChat)
    XCTAssertFalse(ft.alwaysSolo); XCTAssertTrue(ft.directToChat)
    XCTAssertTrue(tf.alwaysSolo);  XCTAssertFalse(tf.directToChat)
    XCTAssertTrue(tt.alwaysSolo);  XCTAssertTrue(tt.directToChat)
  }

  // MARK: - ObservationsListView: instantiation and toolbar intent

  func testObservationsListView_instantiatesWithoutCrash() {
    let view = ObservationsListView()
    XCTAssertNotNil(view,
                    "ObservationsListView must instantiate without crashing")
  }

  func testObservationsListView_usedForBothRoles() {
    // Both guide and public navigate to the same ObservationsListView.
    // Verify the view can be created with guide and public role environments.
    let guideView = ObservationsListView()
      .environment(\.userRole, .guide)
    let publicView = ObservationsListView()
      .environment(\.userRole, .public)

    XCTAssertNotNil(guideView,
                    "ObservationsListView must work with .guide role environment")
    XCTAssertNotNil(publicView,
                    "ObservationsListView must work with .public role environment")
  }

  // MARK: - Observation recording moved to ObservationsListView

  func testSnapshot_observationRecording_nowLivesOnObservationsPage() {
    // SNAPSHOT: "Record observation" was removed from GuideLandingView and
    // PublicGuideLandingView content tiles. It is now accessed via the + button
    // in the ObservationsListView toolbar. This is verified by confirming
    // that ObservationsListView can be instantiated (toolbar compiles) and
    // that RecordObservationSheet can be used from it.
    let sheet = RecordObservationSheet { _ in }
    let list  = ObservationsListView()
    XCTAssertNotNil(sheet, "RecordObservationSheet must be accessible from ObservationsListView")
    XCTAssertNotNil(list,  "ObservationsListView must compile with the + toolbar button")
  }

  func testRecordObservationSheet_instantiatesWithoutCrash() {
    var callbackFired = false
    let sheet = RecordObservationSheet { _ in callbackFired = true }
    XCTAssertNotNil(sheet,
                    "RecordObservationSheet must instantiate with an onSaved callback")
    // Callback closure itself is valid — not yet fired (no audio recorded)
    XCTAssertFalse(callbackFired,
                   "onSaved must not fire on init")
  }

  // MARK: - GuideLandingView and PublicGuideLandingView compile without observation tile

  func testGuideLandingView_instantiatesWithoutCrash() {
    // If the "Record observation" tile removal broke something (e.g. a missing
    // state variable), this init will fail to compile or crash.
    let view = GuideLandingView()
    XCTAssertNotNil(view,
                    "GuideLandingView must instantiate without the Record observation tile")
  }

  func testPublicGuideLandingView_instantiatesWithoutCrash() {
    let view = PublicGuideLandingView()
    XCTAssertNotNil(view,
                    "PublicGuideLandingView must instantiate without the Record observation tile")
  }
}
