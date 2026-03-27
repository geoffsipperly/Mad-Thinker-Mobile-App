// TripDetailView.swift
// Bend Fly Shop
//
// Read-only trip detail view using server DTO.
// Anglers are clickable to view their profiles.

import SwiftUI

// Local TripStatus used for display
private enum TripStatus: String {
  case notStarted = "Not started"
  case inProgress = "In progress"
  case completed = "Completed"
}

struct TripDetailView: View {
  let trip: TripAPI.TripSummary

  @Environment(\.dismiss) private var dismiss

  // Freeze "now" while screen is visible so status doesn't flicker
  @State private var nowSnapshot: Date = .init()

  // MARK: - Status

  private func computeStatus(startStr: String?, endStr: String?, now: Date) -> TripStatus {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    guard let sStr = startStr, let s = iso.date(from: sStr) else { return .notStarted }
    if s > now { return .notStarted }
    let startOfToday = Calendar.current.startOfDay(for: now)
    let end = endStr.flatMap { iso.date(from: $0) }
    let inProgress = (s <= now) && (end == nil || (end ?? now) >= startOfToday)
    return inProgress ? .inProgress : .completed
  }

  private var status: TripStatus {
    computeStatus(startStr: trip.startDate, endStr: trip.endDate, now: nowSnapshot)
  }

  private var anglerArray: [TripAPI.TripSummary.Angler] {
    (trip.anglers ?? []).sorted {
      let lName = [($0.firstName ?? ""), ($0.lastName ?? "")].joined(separator: " ")
      let rName = [($1.firstName ?? ""), ($1.lastName ?? "")].joined(separator: " ")
      return lName < rName
    }
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      List {
        // Trip summary
        Section {
          HStack {
            Text("Lodge")
            Spacer()
            Text(trip.lodge ?? "-")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Trip Name")
            Spacer()
            Text(trip.tripName ?? "-")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Dates")
            Spacer()
            Text("\(dayString(trip.startDate)) – \(dayString(trip.endDate))")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Status")
            Spacer()
            StatusPill(status: status)
          }
        }
        .listRowBackground(Color.black)

        // Anglers list with Classified Waters — clickable to profiles
        Section(header: Text("Anglers")) {
          if anglerArray.isEmpty {
            Text("No anglers listed.")
              .foregroundColor(.secondary)
          } else {
            ForEach(anglerArray, id: \.id) { angler in
              let displayName = [angler.firstName ?? "", angler.lastName ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
              let community = CommunityService.shared.activeCommunityName
              let lodge = CommunityService.shared.activeCommunityName

              NavigationLink {
                AnglerDetailsSheetView(
                  anglerID: angler.id,
                  displayName: displayName.isEmpty ? "(Unnamed)" : displayName,
                  anglerNumber: angler.anglerNumber,
                  community: community,
                  lodge: lodge
                )
              } label: {
                anglerRow(angler: angler)
              }
            }
          }
        }
        .listRowBackground(Color.black)
      }
      .listStyle(.plain)
      .background(Color.black)
      .modifier(HideListBackgroundIfAvailable())
      .environment(\.colorScheme, .dark)
      .navigationTitle("Trip details")
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            dismiss()
          } label: {
            HStack {
              Image(systemName: "chevron.backward")
              Text("Back")
            }
          }
        }
      }
      .onAppear {
        nowSnapshot = Date()
      }
    }
  }

  // MARK: - Helpers

  private func dayString(_ isoStr: String?) -> String {
    guard let s = isoStr else { return "-" }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    guard let d = iso.date(from: s) else { return "-" }
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  @ViewBuilder
  private func anglerRow(angler: TripAPI.TripSummary.Angler) -> some View {
    let displayName = [angler.firstName ?? "", angler.lastName ?? ""]
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    VStack(alignment: .leading, spacing: 8) {
      Text(displayName.isEmpty ? "(Unnamed)" : displayName)
        .font(.body)
        .foregroundColor(.white)

      if !angler.anglerNumber.isEmpty {
        Text("License: \(angler.anglerNumber)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      let licenses = angler.licenses ?? []
      if licenses.isEmpty {
        Text("No Classified Waters licences.")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text("Classified Waters")
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)

          ForEach(licenses, id: \.id) { lic in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(lic.riverName ?? "—") • \(lic.licenseNumber ?? "—")")
                .font(.callout)
                .foregroundColor(.white)
              HStack(spacing: 8) {
                if let from = lic.startDate {
                  Text("From: \(formatDateString(from))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                if let to = lic.endDate {
                  Text("To: \(formatDateString(to))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }
            }
            .padding(.vertical, 2)
          }
        }
        .padding(.top, 2)
      }
    }
    .padding(.vertical, 6)
  }

  private func formatDateString(_ dateStr: String) -> String {
    let ymd = DateFormatter()
    ymd.calendar = Calendar(identifier: .gregorian)
    ymd.dateFormat = "yyyy-MM-dd"
    ymd.timeZone = TimeZone(secondsFromGMT: 0)
    guard let d = ymd.date(from: dateStr) else { return dateStr }
    return d.formatted(date: .abbreviated, time: .omitted)
  }
}

// MARK: - Status pill with consistent colors

private struct StatusPill: View {
  let status: TripStatus

  var body: some View {
    Text(status.rawValue)
      .font(.caption2)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(background)
      .foregroundColor(foreground)
      .clipShape(Capsule())
      .accessibilityLabel("Trip status \(status.rawValue)")
  }

  private var background: Color {
    switch status {
    case .notStarted: Color.yellow.opacity(0.18)
    case .inProgress: Color.green.opacity(0.18)
    case .completed: Color.gray.opacity(0.15)
    }
  }

  private var foreground: Color {
    switch status {
    case .notStarted: .orange
    case .inProgress: .green
    case .completed: .gray
    }
  }
}

// MARK: - Helper: hide list background on iOS 16+

private struct HideListBackgroundIfAvailable: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}
