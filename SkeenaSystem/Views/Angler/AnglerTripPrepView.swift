// Bend Fly Shop
// AnglerTripPrepView.swift
import SwiftUI

// Reads feature flags from Info.plist (populated via xcconfig)
private let FF_FLIGHT_INFO: Bool = readFeatureFlag("FF_FLIGHT_INFO")
private let FF_MEET_STAFF: Bool = readFeatureFlag("FF_MEET_STAFF")
private let FF_GEAR_CHECKLIST: Bool = readFeatureFlag("FF_GEAR_CHECKLIST")
private let FF_MANAGE_LICENSES: Bool = readFeatureFlag("FF_MANAGE_LICENSES")
private let FF_SELF_ASSESSMENT: Bool = readFeatureFlag("FF_SELF_ASSESSMENT")

struct AnglerTripPrepView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.navigateTo) private var navigateTo
  var onClose: (() -> Void)?

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
      ToolbarTab(icon: "bubble.left.and.bubble.right", label: "Community") {
        handleTab(.community)
      }
    }) {
      ScrollView {
        VStack(spacing: 18) {
          AppHeader()
            .padding(.bottom, 10)

          VStack(spacing: 14) {
            if FF_FLIGHT_INFO {
              NavigationLink {
                AnglerFlights()
              } label: {
                prepRow(icon: "airplane", title: "Add flights")
              }
            }

            if FF_MEET_STAFF {
              NavigationLink {
                MeetStaff()
              } label: {
                prepRow(icon: "person.3", title: "Meet staff")
              }
            }

            if FF_GEAR_CHECKLIST {
              NavigationLink {
                GearChecklist()
              } label: {
                prepRow(icon: "bag", title: "Gear checklist")
              }
            }

            if FF_MANAGE_LICENSES {
              NavigationLink {
                AnglerClassifiedWatersLicenseUpload()
              } label: {
                prepRow(icon: "doc.text.magnifyingglass", title: "Manage licenses")
              }
            }

            if FF_SELF_ASSESSMENT {
              NavigationLink {
                AnglerAboutYou()
              } label: {
                prepRow(icon: "person.crop.circle", title: "Self-assessment")
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
