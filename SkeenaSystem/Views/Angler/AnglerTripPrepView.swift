// Bend Fly Shop
// AnglerTripPrepView.swift
import SwiftUI

// Feature flags are now driven by backend community config (with xcconfig fallback).
// See CommunityConfig.flag(_:) for the resolution chain.

struct AnglerTripPrepView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.navigateTo) private var navigateTo
  @ObservedObject private var communityService = CommunityService.shared
  var onClose: (() -> Void)?

  // Reactive entitlements — driven by backend config with xcconfig fallback
  private var E_FLIGHT_INFO: Bool { communityService.activeCommunityConfig.flag("E_FLIGHT_INFO") }
  private var E_MEET_STAFF: Bool { communityService.activeCommunityConfig.flag("E_MEET_STAFF") }
  private var E_GEAR_CHECKLIST: Bool { communityService.activeCommunityConfig.flag("E_GEAR_CHECKLIST") }
  private var E_SELF_ASSESSMENT: Bool { communityService.activeCommunityConfig.flag("E_SELF_ASSESSMENT") }
  private var E_PREFERENCES: Bool { communityService.activeCommunityConfig.flag("E_PREFERENCES") }

  /// When in overlay mode, close the panel first then navigate centrally.
  /// When pushed (no onClose), just use navigateTo directly.
  private func handleTab(_ dest: AnglerDestination?) {
    if let onClose {
      onClose()
      // After closing overlay, navigate if a destination was requested
      if let dest {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          navigateTo(dest)
        }
      }
    } else {
      navigateTo(dest)
    }
  }

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      ToolbarTab(icon: "house", label: "Home") {
        if let onClose {
          onClose()
        } else {
          navigateTo(nil)
        }
      }
      ToolbarTab(icon: "suitcase", label: "My Trip") {
        // Already on My Trip — no-op
      }
      ToolbarTab(icon: "cloud.sun", label: "Conditions") {
        handleTab(.conditions)
      }
      ToolbarTab(icon: "book", label: "Learn") {
        handleTab(.learn)
      }
      ToolbarTab(icon: "message", label: "Social") {
        handleTab(.community)
      }
    }) {
      ScrollView {
        VStack(spacing: 18) {
          AppHeader()
            .padding(.bottom, 10)

          VStack(spacing: 14) {
            if E_FLIGHT_INFO {
              NavigationLink {
                AnglerFlights()
              } label: {
                prepRow(icon: "airplane", title: "Add flights")
              }
            }

            if E_MEET_STAFF {
              NavigationLink {
                MeetStaff()
              } label: {
                prepRow(icon: "person.3", title: "Meet staff")
              }
            }

            if E_GEAR_CHECKLIST {
              NavigationLink {
                GearChecklist()
              } label: {
                prepRow(icon: "bag", title: "Gear checklist")
              }
            }


            if E_SELF_ASSESSMENT {
              NavigationLink {
                AnglerAboutYou()
              } label: {
                prepRow(icon: "person.crop.circle", title: "Self-assessment")
              }
            }

            if E_PREFERENCES {
              NavigationLink {
                ManagePreferencesView()
              } label: {
                prepRow(icon: "slider.horizontal.3", title: "Preferences")
              }
            }

          }
          .padding(.horizontal, 16)

          Spacer()
        }
      }
    }
    .navigationTitle("My Trip")
  }

  private func prepRow(icon: String, title: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title3.weight(.semibold))
        .frame(width: 40, height: 40)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
      Text(title).font(.headline).foregroundColor(.white)
      Spacer()
      Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.6)).font(.subheadline.weight(.semibold))
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 12)
    .background(Color.white.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
  }
}
