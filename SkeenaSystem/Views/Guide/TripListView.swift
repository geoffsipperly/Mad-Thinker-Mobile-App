//
// TripListView.swift
// Bend Fly Shop
//
// Trip list with simplified auto-archive (archive all completed trips) and
// right-aligned status capsules.
//

import SwiftUI
import CoreData

private struct ServerTrip: Identifiable {
  let id: String
  let name: String
  let startDate: Date?
  let endDate: Date?
}

struct TripListView: View {
  @SwiftUI.Environment(\.managedObjectContext) private var context

  @State private var serverTrips: [ServerTrip] = []
  @State private var isLoading = false
  @State private var loadError: String?
  @State private var refreshId = UUID() // toggle to force List rebuild

  @State private var isHydrating = false
  @State private var hydratingTripId: String?
  @State private var hydrationError: String?
  @State private var selectedLocalTrip: Trip?
  @State private var navigateToDetail = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        List {
          if isLoading {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
              .listRowBackground(Color.black)
          } else if let err = loadError {
            Text(err).foregroundColor(.red).listRowBackground(Color.black)
          } else if serverTrips.isEmpty {
            Text("No trips have been set up yet")
              .foregroundColor(.secondary)
              .listRowBackground(Color.black)
          } else {
            let grouped = Dictionary(grouping: serverTrips, by: { status(for: $0) })
            // Desired order of sections
            let order: [RowStatus] = [.inProgress, .notStarted, .completed]
            ForEach(order.filter { grouped[$0] != nil }, id: \.self) { st in
              Section {
                ForEach(grouped[st]!.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }) { trip in
                  Button {
                    hydrateAndOpen(tripId: trip.id)
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
                      HStack(spacing: 10) {
                        if hydratingTripId == trip.id { ProgressView().tint(.white) }
                        Image(systemName: "chevron.right")
                          .font(.footnote.weight(.semibold))
                          .foregroundColor(.white.opacity(0.8))
                      }
                    }
                    .padding(.vertical, 8)
                  }
                  .buttonStyle(.plain)
                  .listRowBackground(Color.black)
                }
              } header: {
                HStack {
                  RowStatusPill(status: st)
                  Spacer()
                }
                .listRowBackground(Color.black)
              }
              .listRowBackground(Color.black)
            }
          }
        }
        .id(refreshId)
        .listStyle(.insetGrouped)
        .modifier(HideListBackgroundIfAvailable())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Manage trips")

        if let hydrationError {
          Text(hydrationError)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.top, 4)
        }
      }
      .navigationDestination(isPresented: $navigateToDetail) {
        if let t = selectedLocalTrip {
          TripDetailView(trip: t)
        }
      }
      .onAppear {
        refreshId = UUID()
        fetchServerTrips()
      }
    }
  }

  private func dayString(_ date: Date?) -> String {
    guard let d = date else { return "-" }
    return d.formatted(date: .abbreviated, time: .omitted)
  }
  
  private func status(for trip: ServerTrip) -> RowStatus {
    let now = Date()
    guard let s = trip.startDate else { return .notStarted }
    if s > now { return .notStarted }
    let startOfToday = Calendar.current.startOfDay(for: now)
    let inProgress = (s <= now) && (trip.endDate == nil || (trip.endDate ?? now) >= startOfToday)
    return inProgress ? .inProgress : .completed
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
        // Map to ServerTrip; assume TripAPI returns objects with tripId, tripName, startDate ISO8601, endDate ISO8601
        let mapped: [ServerTrip] = trips.map { t in
          let id = (t.tripId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
          func parseISO(_ s: String?) -> Date? {
            guard let s = s else { return nil }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
          }
          return ServerTrip(
            id: id,
            name: t.tripName ?? "",
            startDate: parseISO(t.startDate),
            endDate: parseISO(t.endDate)
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

  private func hydrateAndOpen(tripId: String) {
    isHydrating = true
    hydrationError = nil
    Task {
      await MainActor.run { hydratingTripId = tripId }
      await AuthStore.shared.refreshFromSupabase()
      guard let jwt = AuthStore.shared.jwt else {
        await MainActor.run {
          isHydrating = false
          hydratingTripId = nil
          hydrationError = "Not signed in."
        }
        return
      }
      do {
        // Try to fetch just this trip from server
          let serverTrips = try await TripAPI.getTrips(tripId: tripId, jwt: jwt)
        guard let dto = serverTrips.first else { throw NSError(domain: "Hydrate", code: 404, userInfo: [NSLocalizedDescriptionKey: "Trip not found on server"]) }
        // Apply to Core Data on main context
        try await MainActor.run {
          // Find existing or create
          let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
          fetch.fetchLimit = 1
          fetch.predicate = NSPredicate(format: "tripId == %@", UUID(uuidString: dto.tripId ?? "") as CVarArg? ?? NSNull())
          let existing = try? context.fetch(fetch).first
          let local: Trip = existing ?? Trip(context: context)
          if existing == nil { local.tripId = UUID(uuidString: dto.tripId ?? "") ?? UUID() }
          local.name = dto.tripName
          // Dates
          let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
          if let s = dto.startDate, let d = iso.date(from: s) { local.startDate = d }
          if let e = dto.endDate, let d = iso.date(from: e) { local.endDate = d }
          local.guideName = dto.guideName
          // Lodge by name if present
          if let lodgeName = dto.lodge, !lodgeName.isEmpty {
            let lf: NSFetchRequest<Lodge> = Lodge.fetchRequest()
            lf.fetchLimit = 1
            lf.predicate = NSPredicate(format: "name ==[c] %@", lodgeName)
            if let lodge = try? context.fetch(lf).first { local.lodge = lodge }
          }
          // Replace clients/licenses
          if let existingClients = local.clients as? Set<TripClient> {
            for c in existingClients { context.delete(c) }
          }
          if let anglers = dto.anglers {
            for a in anglers {
              let client = TripClient(context: context)
              client.trip = local
              let first = (a.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
              let last = (a.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
              let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
              client.name = full.isEmpty ? nil : full
              client.licenseNumber = a.anglerNumber
              if let licenses = a.licenses {
                for lic in licenses {
                  let cw = ClassifiedWaterLicense(context: context)
                  cw.client = client
                  cw.licNumber = lic.licenseNumber ?? ""
                  cw.water = lic.riverName ?? ""
                  let ymd = DateFormatter(); ymd.calendar = Calendar(identifier: .gregorian); ymd.dateFormat = "yyyy-MM-dd"; ymd.timeZone = TimeZone(secondsFromGMT: 0)
                  if let s = lic.startDate, let d = ymd.date(from: s) { cw.validFrom = d }
                  if let s = lic.endDate, let d = ymd.date(from: s) { cw.validTo = d }
                }
              }
            }
          }
          try context.save()
          self.selectedLocalTrip = local
          self.navigateToDetail = true
        }
      } catch {
        await MainActor.run {
          hydrationError = error.localizedDescription
          hydratingTripId = nil
        }
      }
      await MainActor.run {
        isHydrating = false
        hydratingTripId = nil
      }
    }
  }
}

// MARK: - Row view and status pill

private enum RowStatus: String {
  case notStarted = "Not started"
  case inProgress = "In progress"
  case completed = "Completed"
}

private struct TripRow: View {
  let trip: Trip

  private func dayString(_ date: Date?) -> String {
    guard let d = date else { return "-" }
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  private func status(for trip: Trip) -> RowStatus {
    let now = Date()
    guard let s = trip.startDate else { return .notStarted }
    if s > now { return .notStarted }
    let startOfToday = Calendar.current.startOfDay(for: now)
    let inProgress = (s <= now) && (trip.endDate == nil || (trip.endDate ?? now) >= startOfToday)
    return inProgress ? .inProgress : .completed
  }

  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 6) {
        Text(trip.name ?? "-")
          .foregroundColor(.white)
          .font(.headline)

        Text("\(dayString(trip.startDate)) – \(dayString(trip.endDate))")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      // Right-aligned status capsule for consistent alignment
      // Removed per-row RowStatusPill as per instructions
    }
    .padding(.vertical, 8)
  }
}

private struct RowStatusPill: View {
  let status: RowStatus

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

private struct HideListBackgroundIfAvailable: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}
