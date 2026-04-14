// Bend Fly Shop
//
// TripSyncService.swift
//
// Fetches all trips from the server and hydrates them into Core Data.
// Called at app launch (GuideLandingView) so trips are available before the
// guide taps "Record a Catch".

import CoreData
import Foundation

final class TripSyncService {
  static let shared = TripSyncService()
  private init() {}

  /// True while a sync is in-flight. Prevents overlapping runs.
  private(set) var isSyncing = false

  /// Fetch every trip from the server and upsert into Core Data.
  /// Silently succeeds or fails – callers don't need to handle errors.
  @MainActor
  func syncTripsIfNeeded(context: NSManagedObjectContext) async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }

    do {
      await AuthStore.shared.refreshFromSupabase()
      guard let jwt = AuthStore.shared.jwt else {
        AppLogging.log("[TripSyncService] No JWT – skipping sync", level: .debug, category: .trip)
        return
      }

      // 1. Fetch all trips from the server
      let serverTrips = try await TripAPI.getTrips(jwt: jwt)
      AppLogging.log("[TripSyncService] Fetched \(serverTrips.count) trip(s) from server", level: .info, category: .trip)

      // 2. Collect server trip IDs and upsert each into Core Data
      var serverTripIDs: Set<UUID> = []

      for summary in serverTrips {
        let tripId = (summary.tripId ?? summary.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tripId.isEmpty else { continue }

        if let uuid = UUID(uuidString: tripId) {
          serverTripIDs.insert(uuid)
        }

        do {
          let details = try await TripAPI.getTrips(tripId: tripId, jwt: jwt)
          guard let dto = details.first else { continue }
          upsertTrip(dto, context: context)
        } catch {
          AppLogging.log("[TripSyncService] Failed to hydrate trip \(tripId): \(error.localizedDescription)", level: .warn, category: .trip)
        }
      }

      // 3. Remove local trips that no longer exist on the server
      removeOrphanedTrips(serverTripIDs: serverTripIDs, context: context)

      // 4. Save all changes at once
      if context.hasChanges {
        try context.save()
        AppLogging.log("[TripSyncService] Core Data save succeeded", level: .info, category: .trip)
      }
    } catch {
      AppLogging.log("[TripSyncService] Sync failed: \(error.localizedDescription)", level: .error, category: .trip)
    }
  }

  // MARK: - Upsert a single trip into Core Data

  private func upsertTrip(_ dto: TripAPI.TripSummary, context: NSManagedObjectContext) {
    // Find existing or create
    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    fetch.fetchLimit = 1
    if let tripIdStr = dto.tripId, let uuid = UUID(uuidString: tripIdStr) {
      fetch.predicate = NSPredicate(format: "tripId == %@", uuid as CVarArg)
    } else {
      // Fallback – shouldn't happen, but be safe
      fetch.predicate = NSPredicate(format: "tripId == nil")
    }

    let existing = try? context.fetch(fetch).first
    let local: Trip = existing ?? Trip(context: context)

    if existing == nil {
      if let tripIdStr = dto.tripId, let uuid = UUID(uuidString: tripIdStr) {
        local.tripId = uuid
      } else {
        local.tripId = UUID()
      }
    }

    local.name = dto.tripName
    local.guideName = dto.guideName

    let parsedStart = dto.startDate.flatMap { Self.parseDate($0) }
    let parsedEnd = dto.endDate.flatMap { Self.parseDate($0) }
    local.startDate = parsedStart
    local.endDate = parsedEnd
    AppLogging.log("[TripSyncService] upsert trip '\(dto.tripName ?? "-")' — raw startDate=\(dto.startDate ?? "nil") endDate=\(dto.endDate ?? "nil") → parsed start=\(parsedStart.map { "\($0)" } ?? "nil") end=\(parsedEnd.map { "\($0)" } ?? "nil") existing=\(existing != nil)", level: .info, category: .trip)
    if let c = dto.createdAt, let d = Self.parseDate(c) { local.createdAt = d }

    // Lodge by name – also ensure Community link
    if let lodgeName = dto.lodge, !lodgeName.isEmpty {
      let lf: NSFetchRequest<Lodge> = Lodge.fetchRequest()
      lf.fetchLimit = 1
      lf.predicate = NSPredicate(format: "name ==[c] %@", lodgeName)
      if let lodge = try? context.fetch(lf).first {
        if lodge.community == nil {
          ensureLodgeHasCommunity(lodge, context: context)
        }
        local.lodge = lodge
      }
    }

    // Replace clients / licenses
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
        client.licenseNumber = a.memberId

        if let licenses = a.licenses {
          for lic in licenses {
            let cw = ClassifiedWaterLicense(context: context)
            cw.client = client
            cw.licNumber = lic.licenseNumber ?? ""
            cw.water = lic.riverName ?? ""
            if let s = lic.startDate, let d = DateFormatting.ymd.date(from: s) { cw.validFrom = d }
            if let s = lic.endDate, let d = DateFormatting.ymd.date(from: s) { cw.validTo = d }
          }
        }
      }
    }
  }

  // MARK: - Orphan cleanup

  private func removeOrphanedTrips(serverTripIDs: Set<UUID>, context: NSManagedObjectContext) {
    let fetch: NSFetchRequest<Trip> = Trip.fetchRequest()
    guard let localTrips = try? context.fetch(fetch) else { return }

    var removedCount = 0
    for trip in localTrips {
      guard let tripId = trip.tripId else { continue }
      if !serverTripIDs.contains(tripId) {
        context.delete(trip)
        removedCount += 1
      }
    }

    if removedCount > 0 {
      AppLogging.log("[TripSyncService] Removed \(removedCount) orphaned trip(s) not on server", level: .info, category: .trip)
    }
  }

  // MARK: - Date parsing

  /// Parse ISO8601 (with or without fractional seconds) or date-only "yyyy-MM-dd".
  private static func parseDate(_ s: String) -> Date? {
    DateFormatting.parseISO(s) ?? DateFormatting.ymd.date(from: s)
  }

  // MARK: - Community link helper

  private func ensureLodgeHasCommunity(_ lodge: Lodge, context: NSManagedObjectContext) {
    let cf: NSFetchRequest<Community> = Community.fetchRequest()
    cf.predicate = NSPredicate(format: "name == %@", AppEnvironment.shared.communityName)
    cf.fetchLimit = 1
    if let community = try? context.fetch(cf).first {
      lodge.community = community
    } else {
      let c = Community(context: context)
      c.communityId = UUID()
      c.name = AppEnvironment.shared.communityName
      c.createdAt = Date()
      lodge.community = c
    }
  }
}
