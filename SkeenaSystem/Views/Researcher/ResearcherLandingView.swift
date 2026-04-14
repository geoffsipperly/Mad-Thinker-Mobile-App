// Bend Fly Shop
//
// ResearcherLandingView.swift — Landing screen for the "researcher" role in
// Conservation communities. Jumps directly into the catch recording chat
// with the community logo above it.

import CoreLocation
import SwiftUI
import UIKit

struct ResearcherLandingView: View {
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @StateObject private var chatVM = CatchChatViewModel()
  @StateObject private var loc = LocationManager()

  @State private var showConfirmation = false

  // Path-based nav so the bottom toolbar's "Catches" button can push the
  // reports list the same way guide/public landing views do.
  @State private var navPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navPath) {
      DarkPageTemplate(bottomToolbar: {
        RoleAwareToolbar(activeTab: "home")
      }) {
        VStack(spacing: 0) {
          // ── Header: name (leading) + Conservation Mode (trailing) ─
          VStack(spacing: 0) {
            // Researchers are always in conservation mode — this is a static
            // label, not a toggle, and mirrors the guide landing row.
            HStack(spacing: 12) {
              Text("\(auth.currentFirstName ?? "") \(auth.currentLastName ?? "")")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)

              Spacer()

              Text("Conservation Mode")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
                .accessibilityIdentifier("conservationModeLabel")
            }
            .padding(.horizontal, 20)

            CommunityLogoView(config: communityService.activeCommunityConfig, size: 120)
              .frame(maxWidth: .infinity)
          }
          .padding(.top, 12)

          // ── Catch chat ───────────────────────────────────────────
          CatchChatView(viewModel: chatVM)
        }
      }
      .navigationDestination(for: GuideDestination.self) { dest in
        // Researchers share the publicToolbar layout (Home, Catches, Social,
        // Learn) so we only handle destinations that the toolbar actually
        // exposes. Everything else is EmptyView to fail loud if the toolbar
        // layout changes without a corresponding case here.
        switch dest {
        case .activities:
          ActivitiesView()
            .environment(\.userRole, .researcher)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .community:
          SocialFeedView()
            .environment(\.userRole, .researcher)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .explore:
          ExploreView()
            .environment(\.userRole, .researcher)
            .environment(\.guideNavigateTo, handleNavigateTo)
        case .trips, .observations, .conditions, .learn:
          EmptyView()
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
                .font(.subheadline)
                .foregroundColor(.white)
              Text("Log out")
                .font(.caption)
                .foregroundColor(.white)
            }
          }
          .accessibilityIdentifier("logoutCapsule")
        }
      }
      .onAppear {
        loc.request()
        loc.start()
        chatVM.startConversationIfNeeded()
      }
      .onReceive(loc.$lastLocation) { location in
        chatVM.updateLocation(location)
      }
      .onChange(of: chatVM.saveRequested) { newValue in
        if newValue {
          chatVM.saveRequested = false
          showConfirmation = true
        }
      }
      .fullScreenCover(isPresented: $showConfirmation) {
        ResearcherCatchConfirmationView(
          chatVM: chatVM,
          onConfirm: {
            // Persist the catch to CatchReportStore ONLY on the confirm
            // path — the cancel path deliberately drops it. The store
            // writes to Documents/CatchReportsPicMemo and publishes the
            // new record so ReportsListView picks it up immediately.
            saveResearcherCatchIfPossible()
            showConfirmation = false
            resetForNextCatch()
          },
          onCancel: {
            showConfirmation = false
            resetForNextCatch()
          }
        )
      }
      .tint(.blue)
      .fullScreenCover(isPresented: $chatVM.showRecordObservation, onDismiss: {
        // The sheet can be dismissed via Cancel (no observation saved) or
        // via Save (onSaved fires first). In both cases reset the chat so
        // the researcher sees the Catch / Observation icons again.
        chatVM.resetForNewCatch()
      }) {
        RecordObservationSheet { _ in
          chatVM.showRecordObservation = false
        }
      }
    }
    .environment(\.userRole, .researcher)
    .environment(\.guideNavigateTo, handleNavigateTo)
    .environmentObject(auth)
  }

  // MARK: - Actions

  private func logoutTapped() {
    Task {
      await auth.signOutRemote()
      await MainActor.run {
        AuthStore.shared.clear()
      }
    }
  }

  /// Reset the chat VM so the researcher can record another catch immediately.
  private func resetForNextCatch() {
    chatVM.resetForNewCatch()
  }

  // MARK: - Navigation

  /// Toolbar destination handler shared with ReportsListView / SocialFeedView
  /// via the `guideNavigateTo` environment value. Pops to root on nil, otherwise
  /// replaces the nav path with the tapped destination (matches the guide and
  /// conservation landing view pattern).
  private func handleNavigateTo(_ destination: GuideDestination?) {
    guard let destination else {
      navPath = NavigationPath()
      return
    }
    var newPath = NavigationPath()
    newPath.append(destination)
    navPath = newPath
  }

  // MARK: - Persistence

  /// Persists the current researcher catch via `CatchReportStore.createFromChat`.
  /// Called from the confirmation view's Confirm button before the chat is
  /// reset. Researchers always fish solo, so trip/lodge/guide fields are nil
  /// and memberId comes from `AuthService.shared.currentMemberId`.
  private func saveResearcherCatchIfPossible() {
    guard let snapshot = chatVM.makeCatchSnapshot() else {
      AppLogging.log("[ResearcherSave] makeCatchSnapshot() returned nil — nothing to save", level: .error, category: .catch)
      return
    }

    let memberId = (AuthService.shared.currentMemberId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let communityName = CommunityService.shared.activeCommunityName
    let communityId = CommunityService.shared.activeCommunityId

    AppLogging.log("[ResearcherSave] memberId='\(memberId)' communityId='\(communityId ?? "nil")' communityName='\(communityName ?? "nil")'", level: .debug, category: .catch)
    AppLogging.log("[ResearcherSave] store \(CatchReportStore.shared.bindingDebugDescription)", level: .debug, category: .catch)
    AppLogging.log("[ResearcherSave] snapshot species='\(snapshot.species ?? "nil")' photo='\(snapshot.photoFilename ?? "nil")' headPhoto='\(snapshot.headPhotoFilename ?? "nil")'", level: .debug, category: .catch)

    // Fix: the Combine auto-rebind may not have fired yet if the view
    // appeared before the publisher delivered on the main queue. Force
    // a rebind so the store is scoped before we write.
    if !CatchReportStore.shared.isBound, !memberId.isEmpty, communityId != nil {
      AppLogging.log("[ResearcherSave] store unbound — forcing rebind before save", level: .debug, category: .catch)
      CatchReportStore.shared.rebind(memberId: memberId, communityId: communityId)
    }

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let deviceDescription = "\(UIDevice.current.model) \(UIDevice.current.systemVersion)"

    let reportCountBefore = CatchReportStore.shared.reports.count

    CatchReportStore.shared.createFromChat(
      memberId: memberId.isEmpty ? "Unknown" : memberId,
      species: snapshot.species,
      sex: snapshot.sex,
      lengthInches: snapshot.lengthInches ?? 0,
      lifecycleStage: snapshot.lifecycleStage,
      river: snapshot.riverName,
      classifiedWatersLicenseNumber: nil,
      lat: snapshot.latitude,
      lon: snapshot.longitude,
      photoFilename: snapshot.photoFilename,
      headPhotoFilename: snapshot.headPhotoFilename,
      voiceNoteId: snapshot.voiceNoteId,
      tripId: nil,
      tripName: nil,
      tripStartDate: nil,
      tripEndDate: nil,
      guideName: nil,
      community: communityName,
      communityId: communityId,
      lodge: nil,
      initialRiverName: snapshot.initialRiverName,
      initialSpecies: snapshot.initialSpecies,
      initialLifecycleStage: snapshot.initialLifecycleStage,
      initialSex: snapshot.initialSex,
      initialLengthInches: snapshot.initialLengthInches,
      mlFeatureVector: snapshot.mlFeatureVector,
      lengthSource: snapshot.lengthSource,
      modelVersion: snapshot.modelVersion,
      girthInches: snapshot.girthInches,
      weightLbs: snapshot.weightLbs,
      weightDivisor: snapshot.weightDivisor,
      weightDivisorSource: snapshot.weightDivisorSource,
      girthRatio: snapshot.girthRatio,
      girthRatioSource: snapshot.girthRatioSource,
      initialLengthForMeasurements: snapshot.initialLengthForMeasurements,
      initialGirthInches: snapshot.initialGirthInches,
      initialWeightLbs: snapshot.initialWeightLbs,
      initialWeightDivisor: snapshot.initialWeightDivisor,
      initialWeightDivisorSource: snapshot.initialWeightDivisorSource,
      initialGirthRatio: snapshot.initialGirthRatio,
      initialGirthRatioSource: snapshot.initialGirthRatioSource,
      conservationOptIn: snapshot.conservationOptIn,
      floyId: snapshot.floyId,
      pitId: snapshot.pitId,
      scaleCardId: snapshot.scaleCardId,
      dnaNumber: snapshot.dnaNumber,
      appVersion: appVersion,
      deviceDescription: deviceDescription,
      platform: "iOS",
      catchDate: chatVM.photoTimestamp
    )

    let reportCountAfter = CatchReportStore.shared.reports.count
    AppLogging.log("[ResearcherSave] reports before=\(reportCountBefore) after=\(reportCountAfter) — \(reportCountAfter > reportCountBefore ? "SAVED OK" : "⚠️ REPORT NOT ADDED")", level: .debug, category: .catch)
  }
}
