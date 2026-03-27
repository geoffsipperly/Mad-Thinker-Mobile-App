//
//  CommunityService.swift
//  SkeenaSystem
//
//  Manages community memberships and active community context.
//  After login, fetches user_communities to determine which communities
//  the user belongs to and their role in each.
//

import Foundation
import Combine

final class CommunityService: ObservableObject {
    static let shared = CommunityService()

    // MARK: - Published state

    @Published private(set) var memberships: [CommunityMembership] = []
    @Published var activeCommunityId: String?
    @Published private(set) var activeRole: String?  // "guide" or "angler"
    @Published private(set) var activeCommunityTypeId: String?
    @Published private(set) var activeCommunityConfig: CommunityConfig = .default
    /// True after fetchMemberships() completes (success or failure). Views should
    /// wait for this before rendering community-dependent content.
    @Published private(set) var hasFetchedMemberships = false

    // MARK: - Persistence keys

    private let kActiveCommunityId = "CommunityService.activeCommunityId"
    private let kActiveRole = "CommunityService.activeRole"
    private let kActiveCommunityTypeId = "CommunityService.activeCommunityTypeId"
    private let kActiveCommunityConfig = "CommunityService.activeCommunityConfig"

    // MARK: - Config (lazy to avoid Info.plist crash in test targets)

    private var projectURL: URL { AppEnvironment.shared.projectURL }
    private var anonKey: String { AppEnvironment.shared.anonKey }

    private init() {
        // Restore cached active community on launch
        activeCommunityId = UserDefaults.standard.string(forKey: kActiveCommunityId)
        activeRole = UserDefaults.standard.string(forKey: kActiveRole)
        activeCommunityTypeId = UserDefaults.standard.string(forKey: kActiveCommunityTypeId)

        // Restore cached community config for instant cold-launch rendering
        if let configData = UserDefaults.standard.data(forKey: kActiveCommunityConfig),
           let cached = try? JSONDecoder().decode(CommunityConfig.self, from: configData) {
            activeCommunityConfig = cached
        }

        if let cachedId = activeCommunityId {
            AppLogging.log("[CommunityService] Restored cached community: id=\(cachedId) role=\(activeRole ?? "nil") typeId=\(activeCommunityTypeId ?? "nil") flags=\(activeCommunityConfig.featureFlags.count)", level: .debug, category: .auth)
        }
    }

    // MARK: - Computed properties

    var activeCommunityName: String {
        guard let activeId = activeCommunityId,
              let membership = memberships.first(where: { $0.communityId == activeId }) else {
            return AppEnvironment.shared.communityName
        }
        return membership.communities.name
    }

    var activeMembership: CommunityMembership? {
        guard let activeId = activeCommunityId else { return nil }
        return memberships.first(where: { $0.communityId == activeId })
    }

    var hasMultipleCommunities: Bool {
        memberships.count > 1
    }

    // MARK: - Fetch memberships

    /// Fetches user_communities with joined community info from the REST API.
    /// Call after successful login/token refresh.
    func fetchMemberships() async {
        // --- DIAGNOSTIC: Log pre-fetch state ---
        AppLogging.log("[CommunityService][DIAG] Pre-fetch state: memberships.count=\(memberships.count) activeCommunityId=\(activeCommunityId ?? "nil") hasFetched=\(hasFetchedMemberships)", level: .info, category: .auth)
        if let cachedConfigData = UserDefaults.standard.data(forKey: kActiveCommunityConfig) {
            AppLogging.log("[CommunityService][DIAG] Cached config in UserDefaults: \(cachedConfigData.count) bytes", level: .debug, category: .auth)
        } else {
            AppLogging.log("[CommunityService][DIAG] No cached config in UserDefaults", level: .debug, category: .auth)
        }
        AppLogging.log("[CommunityService][DIAG] Cached activeCommunityId in UserDefaults: \(UserDefaults.standard.string(forKey: kActiveCommunityId) ?? "nil")", level: .debug, category: .auth)

        guard let token = await AuthService.shared.currentAccessToken() else {
            AppLogging.log("[CommunityService] No access token for membership fetch", level: .warn, category: .auth)
            await MainActor.run { self.hasFetchedMemberships = true }
            return
        }

        // --- DIAGNOSTIC: Decode JWT subject (user ID) to verify we're using the right token ---
        if let payload = token.split(separator: ".").dropFirst().first,
           let padded = Data(base64Encoded: String(payload).padding(toLength: ((payload.count + 3) / 4) * 4, withPad: "=", startingAt: 0)),
           let json = try? JSONSerialization.jsonObject(with: padded) as? [String: Any] {
            let sub = json["sub"] as? String ?? "unknown"
            let exp = json["exp"] as? Int ?? 0
            AppLogging.log("[CommunityService][DIAG] JWT sub (user_id)=\(sub) exp=\(exp)", level: .info, category: .auth)
        }

        // Build URL: GET /rest/v1/user_communities with nested joins for branding, geography + feature flags
        var comps = URLComponents(url: projectURL.appendingPathComponent("/rest/v1/user_communities"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,community_id,role,communities(id,name,code,is_active,community_type_id,logo_url,logo_asset_name,tagline,display_name,learn_url,geography,community_types(id,name,feature_flags))")
        ]

        var request = URLRequest(url: comps.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        AppLogging.log("[CommunityService][DIAG] Fetching: \(comps.url?.absoluteString ?? "nil")", level: .debug, category: .auth)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            // --- DIAGNOSTIC: Log raw response ---
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            AppLogging.log("[CommunityService][DIAG] Response status=\(statusCode) body=\(rawBody)", level: .info, category: .auth)

            guard (200..<300).contains(statusCode) else {
                AppLogging.log("[CommunityService] Fetch failed status=\(statusCode) body=\(rawBody)", level: .error, category: .auth)
                await MainActor.run { self.hasFetchedMemberships = true }
                return
            }

            let decoder = JSONDecoder()
            let fetched = try decoder.decode([CommunityMembership].self, from: data)

            await MainActor.run {
                self.memberships = fetched
                AppLogging.log("[CommunityService] Fetched \(fetched.count) membership(s) from server", level: .info, category: .auth)
                for m in fetched {
                    let typeName = m.communities.communityTypes?.name ?? "nil"
                    let flagCount = m.communities.communityTypes?.featureFlags.count ?? 0
                    AppLogging.log("[CommunityService]   • \(m.communities.name) role=\(m.role) type=\(typeName) flags=\(flagCount) logo=\(m.communities.logoUrl ?? "bundled")", level: .debug, category: .auth)
                }

                // Validate cached selection or leave nil so picker is shown
                if let cachedId = self.activeCommunityId {
                    // Validate the cached selection still exists
                    if fetched.contains(where: { $0.communityId == cachedId }) {
                        // Refresh role, type, and config in case they changed
                        if let membership = fetched.first(where: { $0.communityId == cachedId }) {
                            self.activeRole = membership.role
                            self.activeCommunityTypeId = membership.communities.communityTypeId
                            self.activeCommunityConfig = membership.communities.config
                            persistActiveState()
                            let typeName = membership.communities.communityTypes?.name ?? "nil"
                            AppLogging.log("[CommunityService] Refreshed cached community: id=\(cachedId) role=\(membership.role) type=\(typeName) flags=\(self.activeCommunityConfig.featureFlags.count)", level: .debug, category: .auth)
                        }
                    } else {
                        // Cached community no longer valid — clear selection so picker is shown
                        self.activeCommunityId = nil
                        self.activeRole = nil
                        self.activeCommunityTypeId = nil
                        self.activeCommunityConfig = .default
                        persistActiveState()
                        AppLogging.log("[CommunityService] Cached community no longer valid — showing picker for \(fetched.count) communities", level: .info, category: .auth)
                    }
                } else {
                    // No cached selection — show picker
                    AppLogging.log("[CommunityService] No cached selection — \(fetched.count) communities available, showing picker", level: .info, category: .auth)
                }

                self.hasFetchedMemberships = true
            }
        } catch {
            AppLogging.log("[CommunityService] Fetch error: \(error)", level: .error, category: .auth)
            await MainActor.run { self.hasFetchedMemberships = true }
        }
    }

    // MARK: - Set active community

    func setActiveCommunity(id: String) {
        activeCommunityId = id
        let membership = memberships.first(where: { $0.communityId == id })
        activeRole = membership?.role
        activeCommunityTypeId = membership?.communities.communityTypeId
        activeCommunityConfig = membership?.communities.config ?? .default
        persistActiveState()

        // Sync role to AuthService so existing views that read auth.currentUserType continue to work
        if let role = activeRole, let userType = AuthService.UserType(rawValue: role) {
            Task { @MainActor in
                AuthService.shared.updateUserType(userType)
            }
        }

        let typeName = membership?.communities.communityTypes?.name ?? "nil"
        AppLogging.log("[CommunityService] Active community set: id=\(id) role=\(activeRole ?? "nil") type=\(typeName) flags=\(activeCommunityConfig.featureFlags.count) logo=\(activeCommunityConfig.logoUrl ?? "bundled") name=\(activeCommunityName)", level: .info, category: .auth)
    }

    // MARK: - Join community

    /// Join a new community using a 6-char code.
    /// POST /functions/v1/join-community
    func joinCommunity(code: String, role: String = "angler") async throws -> JoinCommunityResponse {
        guard let token = await AuthService.shared.currentAccessToken() else {
            throw CommunityError.unauthenticated
        }

        let url = projectURL.appendingPathComponent("/functions/v1/join-community")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = [
            "community_code": code.uppercased(),
            "role": role
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        let decoded = try JSONDecoder().decode(JoinCommunityResponse.self, from: data)

        switch statusCode {
        case 200:
            AppLogging.log("[CommunityService] Joined community: \(decoded.communityName ?? "?") type=\(decoded.communityType ?? "nil") id=\(decoded.communityId ?? "nil")", level: .info, category: .auth)
            // Refresh memberships to pick up the new one
            await fetchMemberships()
            // Auto-select the newly joined community so the user lands directly in it
            if let newId = decoded.communityId {
                await MainActor.run {
                    setActiveCommunity(id: newId)
                }
            }
            return decoded
        case 409:
            throw CommunityError.alreadyMember(decoded.communityName ?? "Unknown")
        case 404:
            throw CommunityError.invalidCode
        case 400:
            throw CommunityError.invalidCodeFormat
        default:
            throw CommunityError.serverError(statusCode, decoded.error ?? "Unknown error")
        }
    }

    // MARK: - Clear on logout

    func clear() {
        AppLogging.log("[CommunityService] Clearing community state (logout)", level: .info, category: .auth)
        memberships = []
        activeCommunityId = nil
        activeRole = nil
        activeCommunityTypeId = nil
        activeCommunityConfig = .default
        hasFetchedMemberships = false
        UserDefaults.standard.removeObject(forKey: kActiveCommunityId)
        UserDefaults.standard.removeObject(forKey: kActiveRole)
        UserDefaults.standard.removeObject(forKey: kActiveCommunityTypeId)
        UserDefaults.standard.removeObject(forKey: kActiveCommunityConfig)
    }

    // MARK: - Test Support

    /// Injects a community config for testing purposes.
    /// In production, config is set via fetchMemberships() → setActiveCommunity().
    func setTestConfig(_ config: CommunityConfig) {
        activeCommunityConfig = config
    }

    // MARK: - Private

    private func persistActiveState() {
        UserDefaults.standard.set(activeCommunityId, forKey: kActiveCommunityId)
        UserDefaults.standard.set(activeRole, forKey: kActiveRole)
        UserDefaults.standard.set(activeCommunityTypeId, forKey: kActiveCommunityTypeId)
        if let configData = try? JSONEncoder().encode(activeCommunityConfig) {
            UserDefaults.standard.set(configData, forKey: kActiveCommunityConfig)
        }
    }
}

// MARK: - Errors

enum CommunityError: LocalizedError {
    case unauthenticated
    case invalidCode
    case invalidCodeFormat
    case alreadyMember(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Not authenticated. Please log in and try again."
        case .invalidCode:
            return "Community code not found or community is inactive."
        case .invalidCodeFormat:
            return "Invalid code format. Enter a 6-character alphanumeric code."
        case .alreadyMember(let name):
            return "You are already a member of \(name)."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}
