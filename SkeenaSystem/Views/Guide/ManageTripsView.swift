// Bend Fly Shop

import SwiftUI
import CoreData

struct ManageTripsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.managedObjectContext) private var context

  let guideFirstName: String

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "trips")
    }) {
      ScrollView {
        VStack(spacing: 14) {
          AppHeader()
            .padding(.bottom, 10)

          VStack(spacing: 14) {
            // 1) Create new trip -> existing TripFormView
            NavigationLink {
              TripFormView()
            } label: {
              prepRow(icon: "plus.square.on.square", title: "Create new trip")
            }
            .accessibilityIdentifier("createNewTripRow")
            // 2) View / modify trips -> existing TripListView
            NavigationLink {
              TripListView()
            } label: {
              prepRow(icon: "list.bullet.rectangle", title: "Manage existing trips")
            }
            .accessibilityIdentifier("viewModifyTripsRow")
            // 3) View angler profiles for in-progress trips
            NavigationLink {
              AnglerProfilesView()
            } label: {
              prepRow(icon: "person.2.crop.square.stack", title: "View angler profiles")
            }
            .accessibilityIdentifier("viewAnglerProfilesRow")
          }
          .padding(.horizontal, 16)

          Spacer()
        }
      }
    }
    .navigationTitle("Trips")
    .navigationBarBackButtonHidden(true)
  }

  // MARK: - Shared row style (matches LandingView)

  @ViewBuilder
  private func prepRow(icon: String, title: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title3.weight(.semibold))
        .frame(width: 28, height: 28, alignment: .center)
        .padding(10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))

      Text(title)
        .font(.headline.weight(.semibold))
        .foregroundColor(.white)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.footnote.weight(.bold))
        .foregroundColor(.white.opacity(0.8))
    }
    .padding()
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.10), lineWidth: 1)
    )
  }
}
