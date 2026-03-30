// Bend Fly Shop

import SwiftUI
import CoreData

struct ManageTripsView: View {
  @Environment(\.dismiss) private var dismiss

  let guideFirstName: String

  @State private var serverTrips: [ServerTripItem] = []
  @State private var isLoading = false
  @State private var loadError: String?
  @State private var selectedTrip: TripAPI.TripSummary?
  @State private var navigateToDetail = false

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "trips")
    }) {
      VStack(spacing: 0) {
        AppHeader()
          .padding(.bottom, 10)

        if isLoading {
          Spacer()
          ProgressView().tint(.white)
          Spacer()
        } else if let err = loadError {
          Spacer()
          Text(err).foregroundColor(.red).padding()
          Spacer()
        } else if serverTrips.isEmpty {
          Spacer()
          Text("No trips have been set up yet")
            .foregroundColor(.secondary)
          Spacer()
        } else {
          List {
            let grouped = Dictionary(grouping: serverTrips, by: { $0.status })
            let order: [TripRowStatus] = [.inProgress, .notStarted, .completed]
            ForEach(order.filter { grouped[$0] != nil }, id: \.self) { st in
              Section {
                ForEach(grouped[st]!.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }) { trip in
                  Button {
                    selectedTrip = trip.summary
                    navigateToDetail = true
                  } label: {
                    HStack(alignment: .center) {
                      VStack(alignment: .leading, spacing: 6) {
                        Text(trip.name.isEmpty ? "-" : trip.name)
                          .foregroundColor(.white)
                          .font(.headline)
                        Text("\(dayString(trip.startDate)) – \(dayString(trip.endDate))")
                          .font(.caption)
                          .foregroundColor(.secondary)
                      }
                      Spacer()
                      Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.vertical, 8)
                  }
                  .buttonStyle(.plain)
                  .listRowBackground(Color.black)
                }
              } header: {
                HStack {
                  TripStatusPill(status: st)
                  Spacer()
                }
                .listRowBackground(Color.black)
              }
              .listRowBackground(Color.black)
            }
          }
          .listStyle(.insetGrouped)
          .modifier(HideListBackgroundModifier())
          .environment(\.colorScheme, .dark)
        }
      }
    }
    .navigationTitle("Trips")
    .navigationBarBackButtonHidden(true)
    .navigationDestination(isPresented: $navigateToDetail) {
      if let trip = selectedTrip {
        TripDetailView(trip: trip)
      }
    }
    .onAppear { fetchServerTrips() }
  }

  // MARK: - Helpers

  private func dayString(_ date: Date?) -> String {
    guard let d = date else { return "-" }
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  private func fetchServerTrips() {
    isLoading = true
    loadError = nil
    Task {
      await AuthStore.shared.refreshFromSupabase()
      guard let jwt = AuthStore.shared.jwt else {
        await MainActor.run {
          isLoading = false
          loadError = "Not signed in."
          serverTrips = []
        }
        return
      }
      do {
        let trips = try await TripAPI.getTrips(jwt: jwt)
        let mapped: [ServerTripItem] = trips.map { t in
          let iso = ISO8601DateFormatter()
          iso.formatOptions = [.withInternetDateTime]
          return ServerTripItem(
            summary: t,
            name: t.tripName ?? "",
            startDate: t.startDate.flatMap { iso.date(from: $0) },
            endDate: t.endDate.flatMap { iso.date(from: $0) }
          )
        }
        await MainActor.run {
          self.serverTrips = mapped.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
          self.isLoading = false
        }
      } catch {
        await MainActor.run {
          self.isLoading = false
          self.serverTrips = []
          self.loadError = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - View models

private struct ServerTripItem: Identifiable {
  let summary: TripAPI.TripSummary
  let name: String
  let startDate: Date?
  let endDate: Date?

  var id: String { summary.id }

  var status: TripRowStatus {
    let now = Date()
    guard let s = startDate else { return .notStarted }
    let startOfToday = Calendar.current.startOfDay(for: now)
    // Compare start date at day granularity so a trip starting "today" is always in-progress
    let startDay = Calendar.current.startOfDay(for: s)
    if startDay > startOfToday { return .notStarted }
    let inProgress = (startDay <= startOfToday) && (endDate == nil || (endDate ?? now) >= startOfToday)
    return inProgress ? .inProgress : .completed
  }
}

private enum TripRowStatus: String {
  case notStarted = "Not started"
  case inProgress = "In progress"
  case completed = "Completed"
}

private struct TripStatusPill: View {
  let status: TripRowStatus

  var body: some View {
    Text(status.rawValue)
      .font(.caption2)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(backgroundColor)
      .foregroundColor(foregroundColor)
      .clipShape(Capsule())
  }

  private var backgroundColor: Color {
    switch status {
    case .notStarted: return Color.yellow.opacity(0.18)
    case .inProgress: return Color.green.opacity(0.18)
    case .completed: return Color.gray.opacity(0.15)
    }
  }

  private var foregroundColor: Color {
    switch status {
    case .notStarted: return .orange
    case .inProgress: return .green
    case .completed: return .gray
    }
  }
}

// MARK: - Helper: hide list background on iOS 16+

private struct HideListBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}
