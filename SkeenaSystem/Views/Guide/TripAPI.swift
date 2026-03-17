import Foundation

// TripAPI encapsulates the "manage-trip" endpoint for GET/POST operations.
// It mirrors the public contract described in the API docs and is callable from views/view models.

enum TripAPIError: LocalizedError {
    case badRequest(String)
    case unauthorized
    case httpStatus(Int)
    case server(String, String?)
    case decoding(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case let .badRequest(m): return m
        case .unauthorized: return "Unauthorized. Please sign in."
        case let .httpStatus(c): return "Unexpected HTTP \(c)."
        case let .server(m, d): return [m, d].compactMap { $0 }.joined(separator: " • ")
        case let .decoding(m): return "Decoding failed: \(m)"
        case .unknown: return "Request failed."
        }
    }
}

struct TripAPI {
    // Robust config and URL building (mirrors TripRosterAPI normalization)
    private static let rawBaseURLString: String = {
        (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()
    private static let baseURLString: String = {
        var s = rawBaseURLString
        if !s.isEmpty, URL(string: s)?.scheme == nil {
            s = "https://" + s
        }
        return s
    }()
    private static let manageTripPath: String = {
        // Fallback to default path if not provided
        (Bundle.main.object(forInfoDictionaryKey: "MANAGE_TRIP_PATH") as? String) ?? "/functions/v1/manage-trip"
    }()
    static let anonKey: String = {
        // Prefer AppEnvironment if available; fallback to Info.plist API_KEY
        let envKey = AppEnvironment.shared.anonKey
        if !envKey.isEmpty { return envKey }
        return (Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String) ?? ""
    }()

    private static func logConfig() {
        AppLogging.log("[TripAPI] config — API_BASE_URL (raw): '" + rawBaseURLString + "'", level: .debug, category: .trip)
        AppLogging.log("[TripAPI] config — API_BASE_URL (normalized): '" + baseURLString + "'", level: .debug, category: .trip)
        AppLogging.log("[TripAPI] config — manage path: '" + manageTripPath + "'", level: .debug, category: .trip)
    }

    private static func makeURL(queryItems: [URLQueryItem]) throws -> URL {
        guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
            AppLogging.log("[TripAPI] invalid API_BASE_URL — raw: '" + rawBaseURLString + "', normalized: '" + baseURLString + "'", level: .error, category: .trip)
            throw NSError(domain: "TripAPI", code: -1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API_BASE_URL (raw: '" + rawBaseURLString + "', normalized: '" + baseURLString + "')"])
        }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = base.port

        let basePath = base.path
        let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
        let normalizedPath = manageTripPath.hasPrefix("/") ? manageTripPath : "/" + manageTripPath
        comps.path = normalizedBasePath + normalizedPath

        let existing = base.query != nil ? URLComponents(string: base.absoluteString)?.queryItems ?? [] : []
        comps.queryItems = existing + queryItems

        guard let url = comps.url else {
            throw NSError(domain: "TripAPI", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Failed to build manage-trip URL"])
        }
        return url
    }

    // MARK: - Wire models

    struct TripSummary: Decodable, Identifiable {
        let id: String
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
        let anglers: [Angler]?

        struct Angler: Decodable, Identifiable {
            let id: String
            let anglerNumber: String
            let firstName: String?
            let lastName: String?
            let licenses: [License]?

            struct License: Decodable, Identifiable {
                let id: String
                let licenseNumber: String?
                let riverName: String?
                let startDate: String?
                let endDate: String?
            }
        }
    }

    struct GetTripsResponse: Decodable {
        let success: Bool
        let trips: [TripSummary]
    }

    struct UpsertTripRequest: Encodable {
        let tripId: String
        let tripName: String
        let startDate: String?
        let endDate: String?
        let guideName: String?
        let clientName: String?
        let community: String?
        let lodge: String?
        let anglers: [UpsertAngler]

        struct UpsertAngler: Encodable {
            let anglerNumber: String
            let firstName: String?
            let lastName: String?
            let dateOfBirth: String? // YYYY-MM-DD
            let residency: String? // "US", "CA", or "other"
            let sex: String? // "male", "female", or "other"
            let mailingAddress: String?
            let telephoneNumber: String?
            let classifiedWatersLicenses: [UpsertLicense]?

            struct UpsertLicense: Encodable {
                let licenseNumber: String
                let riverName: String
                let startDate: String
                let endDate: String
            }
        }
    }

    struct UpsertTripResponse: Decodable {
        let success: Bool
        let trip: TripSummary?
        let anglers: [TripSummary.Angler]?
    }

    // MARK: - GET trips

    static func getTrips(tripId: String? = nil, community: String? = nil, lodge: String? = nil, jwt: String) async throws -> [TripSummary] {
        logConfig()
        var items: [URLQueryItem] = []
        if let tripId = tripId, !tripId.isEmpty { items.append(URLQueryItem(name: "tripId", value: tripId)) }
        if let community = community, !community.isEmpty { items.append(URLQueryItem(name: "community", value: community)) }
        if let lodge = lodge, !lodge.isEmpty { items.append(URLQueryItem(name: "lodge", value: lodge)) }
        let url = try makeURL(queryItems: items)
        AppLogging.log("[TripAPI] GET trips request URL: \(url.absoluteString)", level: .debug, category: .trip)
        let qi = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&") ?? ""
        AppLogging.log("[TripAPI] Query: \(qi.isEmpty ? "<none>" : qi)", level: .debug, category: .trip)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (data, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse {
          AppLogging.log("[TripAPI] Response status: \(http.statusCode)", level: .debug, category: .trip)
        }
        let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF8>"
        AppLogging.log("[TripAPI] Response body preview (first 512 bytes):\n\(preview)", level: .debug, category: .trip)

        guard let http = resp as? HTTPURLResponse else { throw TripAPIError.unknown }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(GetTripsResponse.self, from: data)
                AppLogging.log("[TripAPI] Decoded trips count: \(decoded.trips.count)", level: .debug, category: .trip)
                if let first = decoded.trips.first {
                  AppLogging.log("[TripAPI] First trip sample: id=\(first.tripId ?? "<nil>"), anglers=\(first.anglers?.count ?? 0)", level: .debug, category: .trip)
                }
                if let first = decoded.trips.first {
                  var dict: [String: Any] = [
                    "id": first.id,
                    "tripId": first.tripId as Any,
                    "tripName": first.tripName as Any,
                    "startDate": first.startDate as Any,
                    "endDate": first.endDate as Any,
                    "guideName": first.guideName as Any,
                    "clientName": first.clientName as Any,
                    "community": first.community as Any,
                    "lodge": first.lodge as Any,
                    "createdAt": first.createdAt as Any,
                    "updatedAt": first.updatedAt as Any
                  ]

                  if let anglers = first.anglers {
                    let anglersArr: [[String: Any]] = anglers.map { a in
                      var aDict: [String: Any] = [
                        "id": a.id,
                        "anglerNumber": a.anglerNumber,
                        "firstName": a.firstName as Any,
                        "lastName": a.lastName as Any
                      ]
                      if let lics = a.licenses {
                        let licArr: [[String: Any]] = lics.map { l in
                          return [
                            "id": l.id,
                            "licenseNumber": l.licenseNumber as Any,
                            "riverName": l.riverName as Any,
                            "startDate": l.startDate as Any,
                            "endDate": l.endDate as Any
                          ]
                        }
                        aDict["licenses"] = licArr
                      }
                      return aDict
                    }
                    dict["anglers"] = anglersArr
                  }

                  if let pretty = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                     let text = String(data: pretty, encoding: .utf8) {
                    AppLogging.log("[TripAPI] First trip (pretty):\n\(text)", level: .debug, category: .trip)
                  } else {
                    AppLogging.log("[TripAPI] First trip: <unable to pretty-print>", level: .debug, category: .trip)
                  }
                }
                return decoded.trips
            } catch {
                throw TripAPIError.decoding(error.localizedDescription)
            }
        case 400: throw TripAPIError.badRequest("Bad request")
        case 401: throw TripAPIError.unauthorized
        default:
            struct ServerErr: Decodable { let error: String; let details: String? }
            if let server = try? JSONDecoder().decode(ServerErr.self, from: data) {
                throw TripAPIError.server(server.error, server.details)
            }
            throw TripAPIError.httpStatus(http.statusCode)
        }
    }

    // MARK: - POST upsert trip

    static func upsertTrip(_ body: UpsertTripRequest, jwt: String) async throws -> UpsertTripResponse {
        let url = try makeURL(queryItems: [])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TripAPIError.unknown }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(UpsertTripResponse.self, from: data)
            } catch {
                throw TripAPIError.decoding(error.localizedDescription)
            }
        case 400: throw TripAPIError.badRequest("Validation error")
        case 401: throw TripAPIError.unauthorized
        case 405: throw TripAPIError.httpStatus(405)
        default:
            struct ServerErr: Decodable { let error: String; let details: String? }
            if let server = try? JSONDecoder().decode(ServerErr.self, from: data) {
                throw TripAPIError.server(server.error, server.details)
            }
            throw TripAPIError.httpStatus(http.statusCode)
        }
    }
}
