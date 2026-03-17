//
// SynchTrips.swift
// Bend Fly Shop
//
// Synchronize trips between local Core Data and remote manage-trip API
// Refactor: compose URL via API_BASE_URL + MANAGE_TRIP_URL (Info.plist)
// Refactor: remove hardcoded anon key (use AuthService.shared.publicAnonKey)
//

import Foundation
import CoreData
import os

public struct SyncSummary {
  public let uploaded: Int
  public let createdLocally: Int
  public let updatedLocally: Int
  public let errors: [String]
  public let details: String

  public init(uploaded: Int = 0, createdLocally: Int = 0, updatedLocally: Int = 0, errors: [String] = [], details: String = "") {
    self.uploaded = uploaded
    self.createdLocally = createdLocally
    self.updatedLocally = updatedLocally
    self.errors = errors
    self.details = details
  }
}

private struct ManageTripsResponse: Codable {
  let success: Bool?
  let trips: [TripDTO]?
  let trip: TripDTO?
  let anglers: [AnglerDTO]?
}

private struct TripDTO: Codable {
  let id: String?
  let tripId: String?
  let tripName: String?
  let startDate: String?
  let endDate: String?
  let guideName: String?
  let clientName: String?
  let community: String?
  let lodge: String?
  let createdAt: String?
  let updatedAt: String?
  let anglers: [AnglerDTO]?
}

private struct AnglerDTO: Codable {
  let id: String?
  let anglerNumber: String?
  let firstName: String?
  let lastName: String?
  let licenses: [LicenseDTO]?
}

private struct LicenseDTO: Codable {
  let id: String?
  let licenseNumber: String?
  let riverName: String?
  let startDate: String?
  let endDate: String?
}

public enum SyncError: Error {
  case missingJWT
  case httpError(status: Int, body: String?)
  case invalidResponse
  case coreDataError(Error)
  case badURL
}

public final class SynchTrips {
  /// Toggle to enable/disable verbose sync logging
  public static var enableVerboseLogging = true

  // MARK: - URL Convention (API_BASE_URL + MANAGE_TRIP_URL)

  private enum ManageTripAPI {
    private static let rawBaseURLString = APIURLUtilities.infoPlistString(forKey: "API_BASE_URL")
    private static let baseURLString = APIURLUtilities.normalizeBaseURL(rawBaseURLString)

    private static let manageTripPath: String = {
      let path = APIURLUtilities.infoPlistString(forKey: "MANAGE_TRIP_URL")
      return path.isEmpty ? "/functions/v1/manage-trip" : path
    }()

    static func url(queryItems: [URLQueryItem] = []) throws -> URL {
      guard let base = URL(string: baseURLString),
            let scheme = base.scheme,
            let host = base.host
      else { throw SyncError.badURL }

      var comps = URLComponents()
      comps.scheme = scheme
      comps.host = host
      comps.port = base.port

      // allow API_BASE_URL to include an optional base path
      let basePath = base.path
      let normalizedBasePath =
        basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)

      let normalizedPath = manageTripPath.hasPrefix("/") ? manageTripPath : "/" + manageTripPath
      comps.path = normalizedBasePath + normalizedPath

      // preserve any query items already present in API_BASE_URL (rare, but safe)
      let existing = base.query != nil
        ? (URLComponents(string: base.absoluteString)?.queryItems ?? [])
        : []

      let merged = existing + queryItems
      comps.queryItems = merged.isEmpty ? nil : merged

      guard let url = comps.url else { throw SyncError.badURL }
      return url
    }
  }

  // MARK: - Auth / Headers

  private static func anonKey() -> String {
    // Preferred: AuthService holds the anon key already
    let k = AuthService.shared.publicAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !k.isEmpty { return k }

    // Alternate fallback if you keep it in AppEnvironment:
    // return AppEnvironment.shared.anonKey

    return ""
  }

  // MARK: - Public API

  public static func synchronize(
    context: NSManagedObjectContext,
    jwt: String,
    community: String? = nil
  ) async throws -> SyncSummary {

    log("Starting synchronization")

    // 1) GET server trips
    let serverTrips = try await fetchServerTrips(jwt: jwt, community: community)
    log("Fetched server trips: \(serverTrips?.count ?? 0)")

    // 2) load local trips
    let localTrips = try await fetchLocalTrips(context: context)
    log("Loaded local trips: \(localTrips.count)")

    // Map local trips by tripId string
    var localByTripId: [String: Trip] = [:]
    for t in localTrips {
      if let id = t.tripId?.uuidString {
        localByTripId[id] = t
      }
    }

    // Map server trips by tripId
    let serverList = serverTrips ?? []
    let serverByTripId: [String: TripDTO] = Dictionary(uniqueKeysWithValues:
      serverList.compactMap { dto in
        guard let tid = dto.tripId?.trimmingCharacters(in: .whitespacesAndNewlines), !tid.isEmpty else { return nil }
        return (tid, dto)
      }
    )

    var errors: [String] = []
    var uploadedCount = 0
    var createdLocally = 0
    var updatedLocally = 0

    // Loop server trips
    for (_, serverTrip) in serverByTripId {
      guard let tripIdStr = serverTrip.tripId, let serverUUID = UUID(uuidString: tripIdStr) else {
        let msg = "Server trip missing/invalid tripId: \(String(describing: serverTrip.tripId))"
        log(msg); errors.append(msg)
        continue
      }

      let serverUpdatedAt = parseISO8601(s: serverTrip.updatedAt) ?? parseISO8601(s: serverTrip.createdAt)
      log("Server trip \(tripIdStr) updatedAt=\(fmt(serverUpdatedAt))")

      if let local = localByTripId[serverUUID.uuidString] {
        // Determine localUpdatedAt
        let localUpdatedAt = local.localUpdatedAt ?? local.createdAt ?? Date.distantPast
        log("Local trip \(local.objectID) tripId=\(local.tripId?.uuidString ?? "<nil>") localUpdatedAt=\(fmt(local.localUpdatedAt)) createdAt=\(fmt(local.createdAt))")

        // Compare server vs local
        if let sUpdated = serverUpdatedAt {
          if sUpdated > localUpdatedAt {
            // Server is newer -> apply server snapshot locally (server wins)
            log("Decision: SERVER WINS for tripId=\(tripIdStr). serverUpdatedAt=\(fmt(sUpdated)) > localUpdatedAt=\(fmt(localUpdatedAt))")
            do {
              try applyServerTripToLocal(serverTrip: serverTrip, localTrip: local, context: context)
              local.localUpdatedAt = serverUpdatedAt
              updatedLocally += 1
              log("Applied server snapshot to local trip \(tripIdStr)")
            } catch {
              let msg = "Failed to apply server trip \(tripIdStr): \(error.localizedDescription)"
              log(msg)
              errors.append(msg)
            }
          } else {
            // Local is same or newer -> push local to server
            log("Decision: LOCAL WINS for tripId=\(tripIdStr). localUpdatedAt=\(fmt(localUpdatedAt)) >= serverUpdatedAt=\(fmt(serverUpdatedAt))")
            do {
              try await postLocalTripToServer(localTrip: local, jwt: jwt)
              local.localUpdatedAt = Date()
              uploadedCount += 1
              log("Posted local trip \(tripIdStr) to server (local won)")
            } catch {
              let msg = "Failed uploading local trip \(local.tripId?.uuidString ?? "<no-id>"): \(error.localizedDescription)"
              log(msg); errors.append(msg)
            }
          }
        } else {
          // Server has no updatedAt -> fallback.
          log("Server has no updatedAt for trip \(tripIdStr). server.createdAt=\(fmt(parseISO8601(s: serverTrip.createdAt)))")
          let serverCreated = parseISO8601(s: serverTrip.createdAt) ?? Date.distantPast
          if localUpdatedAt >= serverCreated {
            log("Decision (fallback): LOCAL WINS for tripId=\(tripIdStr). localUpdatedAt=\(fmt(localUpdatedAt)) >= serverCreatedAt=\(fmt(serverCreated))")
            do {
              try await postLocalTripToServer(localTrip: local, jwt: jwt)
              local.localUpdatedAt = Date()
              uploadedCount += 1
            } catch {
              let msg = "Failed uploading local trip \(local.tripId?.uuidString ?? "<no-id>"): \(error.localizedDescription)"
              log(msg); errors.append(msg)
            }
          } else {
            log("Decision (fallback): SERVER WINS for tripId=\(tripIdStr). serverCreatedAt=\(fmt(serverCreated)) > localUpdatedAt=\(fmt(localUpdatedAt))")
            do {
              try applyServerTripToLocal(serverTrip: serverTrip, localTrip: local, context: context)
              local.localUpdatedAt = serverCreated
              updatedLocally += 1
            } catch {
              let msg = "Failed applying server trip \(tripIdStr): \(error.localizedDescription)"
              log(msg); errors.append(msg)
            }
          }
        }
      } else {
        log("Local doesn't have tripId=\(tripIdStr). Creating local from server snapshot.")
        createLocalTripFromServer(serverTrip: serverTrip, context: context)
        createdLocally += 1
        log("Created local trip from server for tripId=\(tripIdStr)")
      }
    }

    // Push local-only trips
    for local in localTrips {
      if local.tripId == nil {
        local.tripId = UUID()
        log("Assigned new tripId \(local.tripId!.uuidString) to local trip \(local.objectID)")
      }
      let tid = local.tripId!.uuidString
      if serverByTripId[tid] == nil {
        log("Local-only trip \(tid) will be posted to server.")
        do {
          try await postLocalTripToServer(localTrip: local, jwt: jwt)
          local.localUpdatedAt = Date()
          uploadedCount += 1
          log("Posted local-only trip \(tid) to server")
        } catch {
          let msg = "Failed uploading new local trip \(tid): \(error.localizedDescription)"
          log(msg); errors.append(msg)
        }
      }
    }

    // Save changes if any
    do {
      try await saveContextIfNeeded(context: context)
      log("Saved Core Data context after sync")
    } catch {
      log("Failed saving Core Data context: \(error)")
      throw SyncError.coreDataError(error)
    }

    log("Sync complete: uploaded=\(uploadedCount), createdLocally=\(createdLocally), updatedLocally=\(updatedLocally), errors=\(errors.count)")
    return SyncSummary(
      uploaded: uploadedCount,
      createdLocally: createdLocally,
      updatedLocally: updatedLocally,
      errors: errors,
      details: "Uploaded: \(uploadedCount), Created locally: \(createdLocally), Updated locally: \(updatedLocally)"
    )
  }

  // MARK: - Networking

  private static func fetchServerTrips(jwt: String, community: String?) async throws -> [TripDTO]? {
    var q: [URLQueryItem] = []
    if let community = community, !community.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      q.append(URLQueryItem(name: "community", value: community))
    }

    let url = try ManageTripAPI.url(queryItems: q)

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    req.setValue(anonKey(), forHTTPHeaderField: "apikey")

    log("GET \(req.url?.absoluteString ?? "<unknown>")")
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
    guard (200...299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8)
      log("GET failed status=\(http.statusCode) body=\(body ?? "<empty>")")
      throw SyncError.httpError(status: http.statusCode, body: body)
    }

    if enableVerboseLogging {
      let raw = String(data: data, encoding: .utf8) ?? "<binary>"
      log("GET response raw:\n\(truncate(raw))")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(ManageTripsResponse.self, from: data)

    if enableVerboseLogging {
      if let trips = resp.trips ?? (resp.trip.map { [$0] }) {
        for t in trips {
          let tid = t.tripId ?? t.id ?? "<nil>"
          log("Decoded Trip tripId=\(tid) anglers count=\(t.anglers?.count ?? -1)")
          if let anglers = t.anglers {
            for a in anglers {
              let angNum = a.anglerNumber ?? "<nil>"
              log("  Angler anglerNumber=\(angNum) licenses count=\(a.licenses?.count ?? -1)")
            }
          }
        }
      } else {
        log("Decoded response contained no trips")
      }
    }

    if let trips = resp.trips { return trips }
    if let single = resp.trip { return [single] }
    return nil
  }

  private static func postLocalTripToServer(localTrip: Trip, jwt: String) async throws {
    let body = try buildPostBody(from: localTrip)
    if enableVerboseLogging {
      let bodyStr = String(data: body, encoding: .utf8) ?? "<binary>"
      log("POST body for tripId=\(localTrip.tripId?.uuidString ?? "<nil>"):\n\(truncate(bodyStr))")
    }

    let url = try ManageTripAPI.url()

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    req.setValue(anonKey(), forHTTPHeaderField: "apikey")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = body

    log("POST \(req.url?.absoluteString ?? "<unknown>") for tripId=\(localTrip.tripId?.uuidString ?? "<nil>")")
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
    guard (200...299).contains(http.statusCode) else {
      let bodyStr = String(data: data, encoding: .utf8)
      log("POST failed status=\(http.statusCode) body=\(bodyStr ?? "<empty>")")
      throw SyncError.httpError(status: http.statusCode, body: bodyStr)
    }

    if enableVerboseLogging {
      let respStr = String(data: data, encoding: .utf8) ?? "<binary>"
      log("POST response for tripId=\(localTrip.tripId?.uuidString ?? "<nil>") status=\(http.statusCode) body=\n\(truncate(respStr))")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    if let resp = try? decoder.decode(ManageTripsResponse.self, from: data) {
      if enableVerboseLogging {
        if let t = resp.trips?.first ?? resp.trip {
          log("POST decoded trip tripId=\(t.tripId ?? t.id ?? "<nil>") anglers count=\(t.anglers?.count ?? -1)")
        } else {
          log("POST decoded ManageTripsResponse without trip object")
        }
      }
      if let tripDTO = resp.trips?.first ?? resp.trip {
        await applyServerTripToLocalAsync(serverTrip: tripDTO, localTrip: localTrip, context: localTrip.managedObjectContext)
        log("Applied server canonical trip after POST for local tripId=\(localTrip.tripId?.uuidString ?? "<nil>")")
        return
      }
    }

    struct PostResponse: Codable {
      let success: Bool?
      let trip: TripDTO?
    }
    if let post = try? decoder.decode(PostResponse.self, from: data), let t = post.trip {
      if enableVerboseLogging {
        log("POST decoded PostResponse trip tripId=\(t.tripId ?? t.id ?? "<nil>") anglers count=\(t.anglers?.count ?? -1)")
      }
      await applyServerTripToLocalAsync(serverTrip: t, localTrip: localTrip, context: localTrip.managedObjectContext)
      log("Applied server canonical trip (PostResponse) after POST for local tripId=\(localTrip.tripId?.uuidString ?? "<nil>")")
    }
  }

  // MARK: - Core Data apply/create helpers (unchanged)

  private static func applyServerTripToLocal(serverTrip: TripDTO, localTrip: Trip, context: NSManagedObjectContext?) throws {
    guard let ctx = context else { return }
    ctx.performAndWait {
      log("applyServerTripToLocal tripId=\(serverTrip.tripId ?? serverTrip.id ?? "<nil>") incoming anglers count=\(serverTrip.anglers?.count ?? -1)")

      if let tripName = serverTrip.tripName { localTrip.name = tripName }
      if let guide = serverTrip.guideName { localTrip.guideName = guide }
      if let lodgeName = serverTrip.lodge, !lodgeName.isEmpty {
        let lf: NSFetchRequest<Lodge> = Lodge.fetchRequest()
        lf.fetchLimit = 1
        lf.predicate = NSPredicate(format: "name ==[c] %@", lodgeName)
        if let lodge = try? ctx.fetch(lf).first {
          // Ensure the Lodge is linked to its Community (may be nil
          // if the Lodge was created before seedCommunityIfNeeded ran).
          if lodge.community == nil {
            ensureLodgeHasCommunity(lodge, context: ctx)
          }
          localTrip.lodge = lodge
        }
      }

      if let s = serverTrip.startDate, let sd = parseISO8601(s: s) { localTrip.startDate = sd }
      if let e = serverTrip.endDate, let ed = parseISO8601(s: e) { localTrip.endDate = ed }

      if let tId = serverTrip.tripId, let uuid = UUID(uuidString: tId) { localTrip.tripId = uuid }

      if let created = parseISO8601(s: serverTrip.createdAt) { localTrip.createdAt = created }
      if let updated = parseISO8601(s: serverTrip.updatedAt) { localTrip.localUpdatedAt = updated }

      if let anglers = serverTrip.anglers {
        if let existingClients = localTrip.clients as? Set<TripClient> {
          log("Deleting \(existingClients.count) existing local clients before applying \(anglers.count) server anglers")
          for c in existingClients { ctx.delete(c) }
        }
        for a in anglers {
          let client = TripClient(context: ctx)
          client.trip = localTrip
          let first = (a.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let last = (a.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
          client.name = full.isEmpty ? nil : full
          client.licenseNumber = a.anglerNumber

          if let licenses = a.licenses {
            for lic in licenses {
              let cw = ClassifiedWaterLicense(context: ctx)
              cw.client = client
              cw.licNumber = lic.licenseNumber ?? ""
              cw.water = lic.riverName ?? ""
              if let s = lic.startDate, let d = parseYMD(s: s) { cw.validFrom = d }
              if let s = lic.endDate, let d = parseYMD(s: s) { cw.validTo = d }
            }
          } else {
            log("  Server angler \(a.anglerNumber ?? "<nil>") has no licenses array in payload")
          }
        }
      } else {
        log("Server provided no anglers; preserving existing local clients for tripId=\(serverTrip.tripId ?? serverTrip.id ?? "<nil>")")
      }
    }
  }

  private static func createLocalTripFromServer(serverTrip: TripDTO, context: NSManagedObjectContext) {
    context.performAndWait {
      let trip = Trip(context: context)
      if let tId = serverTrip.tripId, let uuid = UUID(uuidString: tId) { trip.tripId = uuid } else { trip.tripId = UUID() }

      if let tripName = serverTrip.tripName { trip.name = tripName }
      if let guide = serverTrip.guideName { trip.guideName = guide }
      if let s = serverTrip.startDate, let sd = parseISO8601(s: s) { trip.startDate = sd }
      if let e = serverTrip.endDate, let ed = parseISO8601(s: e) { trip.endDate = ed }
      if let created = parseISO8601(s: serverTrip.createdAt) { trip.createdAt = created }
      if let updated = parseISO8601(s: serverTrip.updatedAt) { trip.localUpdatedAt = updated }

      if let lodgeName = serverTrip.lodge, !lodgeName.isEmpty {
        let lf: NSFetchRequest<Lodge> = Lodge.fetchRequest()
        lf.fetchLimit = 1
        lf.predicate = NSPredicate(format: "name ==[c] %@", lodgeName)
        if let lodge = try? context.fetch(lf).first {
          if lodge.community == nil {
            ensureLodgeHasCommunity(lodge, context: context)
          }
          trip.lodge = lodge
        }
      }

      if let anglers = serverTrip.anglers {
        for a in anglers {
          let client = TripClient(context: context)
          client.trip = trip
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
              if let s = lic.startDate, let d = parseYMD(s: s) { cw.validFrom = d }
              if let s = lic.endDate, let d = parseYMD(s: s) { cw.validTo = d }
            }
          }
        }
      }
    }
  }

  /// If a Lodge has no Community relationship, look up (or create) the
  /// "Bend Fly Shop" Community and link it. This covers Lodges that were
  /// created by a previous sync before seedCommunityIfNeeded had run.
  private static func ensureLodgeHasCommunity(_ lodge: Lodge, context: NSManagedObjectContext) {
    let cf: NSFetchRequest<Community> = Community.fetchRequest()
    let communityName = AppEnvironment.shared.communityName
    cf.predicate = NSPredicate(format: "name == %@", communityName)
    cf.fetchLimit = 1
    if let community = try? context.fetch(cf).first {
      lodge.community = community
      log("ensureLodgeHasCommunity: linked '\(lodge.name ?? "")' to existing \(communityName) community")
    } else {
      let c = Community(context: context)
      c.communityId = UUID()
      c.name = communityName
      c.createdAt = Date()
      lodge.community = c
      log("ensureLodgeHasCommunity: created \(communityName) community and linked '\(lodge.name ?? "")'")
    }
  }

  private static func applyServerTripToLocalAsync(serverTrip: TripDTO, localTrip: Trip, context: NSManagedObjectContext?) async {
    guard let ctx = context else { return }
    let objectID = localTrip.objectID
    await withCheckedContinuation { cont in
      ctx.perform {
        do {
          if let refreshedTrip = try? ctx.existingObject(with: objectID) as? Trip {
            try applyServerTripToLocal(serverTrip: serverTrip, localTrip: refreshedTrip, context: ctx)
          }
        } catch {
          // best-effort
        }
        cont.resume()
      }
    }
  }

  // MARK: - POST body builder (unchanged)

  private static func buildPostBody(from localTrip: Trip) throws -> Data {
    var dict: [String: Any] = [:]

    let tripIdStr: String
    if let t = localTrip.tripId { tripIdStr = t.uuidString } else {
      let new = UUID()
      localTrip.tripId = new
      tripIdStr = new.uuidString
    }
    dict["tripId"] = tripIdStr
    dict["tripName"] = localTrip.name ?? ""

    if let s = localTrip.startDate { dict["startDate"] = iso8601String(from: s) }
    if let e = localTrip.endDate { dict["endDate"] = iso8601String(from: e) }

    if let guide = localTrip.guideName { dict["guideName"] = guide }

    var communityValue: String?
    if localTrip.entity.attributesByName["community"] != nil {
      if let c = localTrip.value(forKey: "community") as? String {
        let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { communityValue = trimmed }
      }
    }
    if communityValue == nil || communityValue?.isEmpty == true {
      communityValue = AppEnvironment.shared.communityName
    }
    dict["community"] = communityValue!

    if let lodgeName = localTrip.lodge?.name { dict["lodge"] = lodgeName }

    var anglersArray: [[String: Any]] = []
    if let clients = localTrip.clients as? Set<TripClient> {
      for client in clients {
        var c: [String: Any] = [:]
        let anglerNumber = (client.licenseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        c["anglerNumber"] = anglerNumber

        var cwArray: [[String: Any]] = []
        if let rows = client.classifiedLicenses as? Set<ClassifiedWaterLicense> {
          for cw in rows {
            var cwD: [String: Any] = [:]
            cwD["licenseNumber"] = cw.licNumber ?? ""
            cwD["riverName"] = cw.water ?? ""
            if let from = cw.validFrom { cwD["startDate"] = ymdString(from: from) }
            if let to = cw.validTo { cwD["endDate"] = ymdString(from: to) }
            cwArray.append(cwD)
          }
        }
        if !cwArray.isEmpty { c["classifiedWatersLicenses"] = cwArray }
        anglersArray.append(c)
      }
    }
    dict["anglers"] = anglersArray

    return try JSONSerialization.data(withJSONObject: dict, options: [])
  }

  // MARK: - Core Data utility helpers

  private static func fetchLocalTrips(context: NSManagedObjectContext) async throws -> [Trip] {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Trip], Error>) in
      context.perform {
        do {
          let req: NSFetchRequest<Trip> = Trip.fetchRequest()
          let res = try context.fetch(req)
          continuation.resume(returning: res)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func saveContextIfNeeded(context: NSManagedObjectContext) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      context.perform {
        if context.hasChanges {
          do {
            try context.save()
            continuation.resume(returning: ())
          } catch {
            continuation.resume(throwing: error)
          }
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  // MARK: - Parsing & formatting helpers

  private static func parseISO8601(s: String?) -> Date? {
    guard let s = s else { return nil }
    let iso1 = ISO8601DateFormatter()
    iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso1.date(from: s) { return d }
    let iso2 = ISO8601DateFormatter()
    iso2.formatOptions = [.withInternetDateTime]
    return iso2.date(from: s)
  }

  private static func parseYMD(s: String?) -> Date? {
    guard let s = s else { return nil }
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(secondsFromGMT: 0)
    return df.date(from: s)
  }

  private static func iso8601String(from date: Date) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    iso.timeZone = TimeZone(secondsFromGMT: 0)
    return iso.string(from: date)
  }

  private static func ymdString(from date: Date) -> String {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(secondsFromGMT: 0)
    return df.string(from: date)
  }

  // MARK: - Logging helpers

  private static func log(_ msg: String) {
    guard enableVerboseLogging else { return }
    AppLogging.log(msg, level: .debug, category: .trip)
  }

  private static func fmt(_ d: Date?) -> String {
    guard let d = d else { return "<nil>" }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: d)
  }

  private static func truncate(_ s: String, max: Int = 2000) -> String {
    if s.count <= max { return s }
    let idx = s.index(s.startIndex, offsetBy: max)
    return String(s[..<idx]) + "...[truncated]"
  }
}
