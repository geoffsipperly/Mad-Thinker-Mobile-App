// Bend Fly Shop
//
// ResearcherLandingView.swift — Landing screen for the "researcher" role in
// Conservation communities. Jumps directly into the catch recording chat
// with the community logo above it.

import CoreLocation
import SwiftUI

struct ResearcherLandingView: View {
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @StateObject private var chatVM = CatchChatViewModel()
  @StateObject private var loc = LocationManager()

  @State private var showConfirmation = false

  var body: some View {
    NavigationStack {
      DarkPageTemplate(bottomToolbar: {
        RoleAwareToolbar(activeTab: "home")
      }) {
        VStack(spacing: 0) {
          // ── Header: name + logo ──────────────────────────────────
          VStack(spacing: 0) {
            Text("\(auth.currentFirstName ?? "") \(auth.currentLastName ?? "")")
              .font(.caption.weight(.semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 20)

            Text("Researcher Mode")
              .font(.caption.weight(.semibold))
              .foregroundColor(.blue)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 20)

            CommunityLogoView(config: communityService.activeCommunityConfig, size: 120)
              .frame(maxWidth: .infinity)
          }
          .padding(.top, 12)

          // ── Catch chat ───────────────────────────────────────────
          CatchChatView(viewModel: chatVM)
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
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
              Text("Log out")
                .font(.footnote.weight(.semibold))
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
    }
    .environment(\.userRole, .researcher)
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
}
