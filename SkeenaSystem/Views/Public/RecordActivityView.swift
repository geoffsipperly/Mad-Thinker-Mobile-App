// Bend Fly Shop

import CoreLocation
import SwiftUI

// MARK: - RecordActivityView
//
// Pushed from PublicLandingView when the user taps "Record new activity".
// Presents all activity tiles: Record a Catch, Observations, and the four
// no-catch event types (Active, Farmed, Promising, Passed).

struct RecordActivityView: View {
  @StateObject private var auth = AuthService.shared
  @Environment(\.guideNavigateTo) private var guideNavigateTo
  @Environment(\.dismiss) private var dismiss

  // Location for no-catch reports
  @StateObject private var locationManager = LocationManager()

  // Navigation
  @State private var goToAssistant = false

  // No-catch tile feedback
  @State private var savedEventType: NoCatchEventType? = nil

  var body: some View {
    DarkPageTemplate {
      ScrollView {
        VStack(spacing: 12) {
          // Action tiles — Record a Catch + Record Observation (blue)
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button { goToAssistant = true } label: {
              actionTile(icon: "square.and.pencil", label: "Record catch")
            }
            .accessibilityIdentifier("landedTile")

            Button { guideNavigateTo(.observations) } label: {
              actionTile(icon: "waveform", label: "Record Observation")
            }
            .accessibilityIdentifier("observationsTile")
          }
          .padding(.horizontal, 16)
          .padding(.top, 16)

          // Section divider
          Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.vertical, 4)

          // No-catch event tiles — 2 per row
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(NoCatchEventType.allCases, id: \.self) { eventType in
              Button { logNoCatchReport(eventType: eventType) } label: {
                noCatchTile(eventType: eventType)
              }
              .disabled(savedEventType != nil)
              .accessibilityIdentifier("\(eventType.rawValue)Tile")
            }
          }
          .padding(.horizontal, 16)

          Spacer(minLength: 24)

          // Explanatory text
          VStack(alignment: .leading, spacing: 12) {
            ForEach([
              ("eye",                  "Active",     "You saw signs of fish but didn't hook up."),
              ("leaf.arrow.circlepath","Farmed",     "You hooked a fish but lost it before landing."),
              ("sparkles",             "Promising",  "The spot looked promising and you want to remember it."),
              ("xmark.circle",         "Passed",     "You checked the spot and decided to move on."),
            ], id: \.1) { icon, title, description in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.5))
                  .frame(width: 16, alignment: .center)
                  .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                  Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                  Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
        }
      }
    }
    .navigationTitle("New Activity")
    .navigationDestination(isPresented: $goToAssistant) {
      ReportChatView(alwaysSolo: true, directToChat: true, onSaved: {
        // Pop all the way back to the landing view after catch is saved
        goToAssistant = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          dismiss()
        }
      })
        .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear {
      locationManager.request()
      locationManager.start()
    }
  }

  // MARK: - Actions

  private func logNoCatchReport(eventType: NoCatchEventType) {
    let report = FarmedReport(
      id: UUID(),
      createdAt: Date(),
      status: .savedLocally,
      eventType: eventType,
      guideName: auth.currentFirstName ?? "",
      lat: locationManager.lastLocation?.coordinate.latitude,
      lon: locationManager.lastLocation?.coordinate.longitude,
      memberId: auth.currentMemberId,
      communityId: CommunityService.shared.activeCommunityId
    )
    FarmedReportStore.shared.add(report)

    savedEventType = eventType
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      savedEventType = nil
    }
  }

  // MARK: - Tile views

  private func actionTile(icon: String, label: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.blue)
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundColor(.blue)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 70)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }

  private func noCatchTile(eventType: NoCatchEventType) -> some View {
    let icon: String = {
      switch eventType {
      case .active:    return "eye"
      case .farmed:    return "leaf.arrow.circlepath"
      case .promising: return "sparkles"
      case .passed:    return "xmark.circle"
      }
    }()
    return VStack(spacing: 6) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.white)
      Text(savedEventType == eventType ? "Saved!" : eventType.displayName)
        .font(.caption.weight(.semibold))
        .foregroundColor(.white)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 70)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }
}
