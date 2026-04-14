//
//  OpsTicketsAPI.swift
//  SkeenaSystem
//
//  API service for the ops-tickets edge function.
//  Manages operational tickets (Kanban tasks) for a community.
//

import Foundation

// MARK: - Error

enum OpsTicketsError: LocalizedError {
    case badRequest(String)
    case unauthorized
    case httpStatus(Int)
    case server(String)
    case decoding(String)
    case noCommunity
    case unknown

    var errorDescription: String? {
        switch self {
        case let .badRequest(m): return m
        case .unauthorized: return "Unauthorized. Please sign in."
        case let .httpStatus(c): return "Unexpected HTTP \(c)."
        case let .server(m): return m
        case let .decoding(m): return "Decoding failed: \(m)"
        case .noCommunity: return "No active community selected."
        case .unknown: return "Request failed."
        }
    }
}

// MARK: - Models

struct OpsTicket: Codable, Identifiable, Equatable {
    let id: String
    let communityId: String
    var taskName: String
    var description: String?
    var ownerUserId: String?
    var ownerName: String?
    var dueDate: String?
    var notes: String?
    var stage: String
    var isArchived: Bool
    let createdAt: String?
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case communityId = "community_id"
        case taskName = "task_name"
        case description
        case ownerUserId = "owner_user_id"
        case ownerName = "owner_name"
        case dueDate = "due_date"
        case notes
        case stage
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case createdBy = "created_by"
    }
}

struct TicketOwner: Codable, Identifiable, Equatable {
    let userId: String
    let firstName: String
    let lastName: String
    let role: String?

    /// Display name combining first + last name.
    var name: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case role
    }
}

// MARK: - API

struct OpsTicketsAPI {

    private static var anonKey: String { AppEnvironment.shared.anonKey }

    private static func jwt() throws -> String {
        guard let token = AuthStore.shared.jwt, !token.isEmpty else {
            throw OpsTicketsError.unauthorized
        }
        return token
    }

    private static func communityId() throws -> String {
        guard let id = CommunityService.shared.activeCommunityId else {
            throw OpsTicketsError.noCommunity
        }
        return id
    }

    // MARK: - HTTP helpers

    private static func post(_ body: [String: Any]) async throws -> Data {
        let url = AppEnvironment.shared.opsTicketsURL
        let token = try jwt()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLogging.log("[OpsTicketsAPI] POST \(url.path) action=\(body["action"] ?? "?")", level: .debug, category: .auth)

        let (data, resp) = try await URLSession.shared.data(for: request)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            AppLogging.log("[OpsTicketsAPI] Error status=\(code) body=\(msg)", level: .error, category: .auth)
            switch code {
            case 400: throw OpsTicketsError.badRequest(msg)
            case 401, 403: throw OpsTicketsError.unauthorized
            default: throw OpsTicketsError.httpStatus(code)
            }
        }

        return data
    }

    // MARK: - Actions

    /// Lists non-archived tickets for the active community.
    static func listTickets() async throws -> [OpsTicket] {
        let body: [String: Any] = [
            "action": "list_tickets",
            "community_id": try communityId(),
            "include_archived": false
        ]
        let data = try await post(body)

        struct ListResponse: Decodable {
            let tickets: [OpsTicket]?
            let ticket: OpsTicket? // single-ticket fallback
        }

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        if let tickets = decoded.tickets { return tickets }
        if let ticket = decoded.ticket { return [ticket] }
        // Try decoding as raw array
        if let tickets = try? JSONDecoder().decode([OpsTicket].self, from: data) { return tickets }
        return []
    }

    /// Creates a new ticket. Returns the created ticket.
    static func createTicket(
        taskName: String,
        description: String?,
        ownerUserId: String?,
        dueDate: String?,
        notes: String?
    ) async throws -> OpsTicket {
        var body: [String: Any] = [
            "action": "create_ticket",
            "community_id": try communityId(),
            "task_name": taskName
        ]
        if let d = description, !d.isEmpty { body["description"] = d }
        if let o = ownerUserId { body["owner_user_id"] = o }
        if let dd = dueDate, !dd.isEmpty { body["due_date"] = dd }
        if let n = notes, !n.isEmpty { body["notes"] = n }

        let data = try await post(body)

        struct CreateResponse: Decodable { let ticket: OpsTicket }
        let decoded = try JSONDecoder().decode(CreateResponse.self, from: data)
        return decoded.ticket
    }

    /// Updates an existing ticket. Only sends changed fields.
    static func updateTicket(
        ticketId: String,
        taskName: String? = nil,
        description: String? = nil,
        ownerUserId: String? = nil,
        dueDate: String? = nil,
        notes: String? = nil,
        stage: String? = nil,
        isArchived: Bool? = nil
    ) async throws -> OpsTicket {
        var body: [String: Any] = [
            "action": "update_ticket",
            "community_id": try communityId(),
            "ticket_id": ticketId
        ]
        if let v = taskName { body["task_name"] = v }
        if let v = description { body["description"] = v }
        if let v = ownerUserId { body["owner_user_id"] = v }
        if let v = dueDate { body["due_date"] = v }
        // Always send notes (even empty string) so the server clears/updates them
        if let v = notes { body["notes"] = v }
        if let v = stage { body["stage"] = v }
        if let v = isArchived { body["is_archived"] = v }

        let data = try await post(body)

        struct UpdateResponse: Decodable { let ticket: OpsTicket }
        let decoded = try JSONDecoder().decode(UpdateResponse.self, from: data)
        return decoded.ticket
    }

    /// Gets available ticket owners (guides + community admins).
    static func getOwners() async throws -> [TicketOwner] {
        let cid = try communityId()
        AppLogging.log("[OpsTicketsAPI] get_owners -> community_id=\(cid)", level: .debug, category: .auth)

        let body: [String: Any] = [
            "action": "get_owners",
            "community_id": cid
        ]
        let data = try await post(body)

        let rawBody = String(data: data, encoding: .utf8) ?? "<unable to decode>"
        AppLogging.log("[OpsTicketsAPI] get_owners response body: \(rawBody)", level: .debug, category: .auth)

        struct OwnersResponse: Decodable { let owners: [TicketOwner]? }
        if let decoded = try? JSONDecoder().decode(OwnersResponse.self, from: data),
           let owners = decoded.owners {
            AppLogging.log("[OpsTicketsAPI] get_owners decoded \(owners.count) owner(s): \(owners.map { "\($0.name) (\($0.userId))" }.joined(separator: ", "))", level: .info, category: .auth)
            return owners
        }
        // Fallback: raw array
        if let owners = try? JSONDecoder().decode([TicketOwner].self, from: data) {
            AppLogging.log("[OpsTicketsAPI] get_owners decoded \(owners.count) owner(s) via fallback array", level: .info, category: .auth)
            return owners
        }
        AppLogging.log("[OpsTicketsAPI] get_owners: failed to decode any owners from response", level: .error, category: .auth)
        return []
    }
}
