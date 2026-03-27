//
//  CommunityConfig.swift
//  SkeenaSystem
//
//  Unified community configuration that merges branding (from communities table)
//  and feature flags (from community_types table). Provides typed accessors with
//  xcconfig fallback so communities without backend config behave identically
//  to the current static system.
//

import Foundation

struct CommunityConfig: Codable, Equatable {

    // MARK: - Branding (from communities table)

    let logoUrl: String?
    let logoAssetName: String?
    let tagline: String?
    let displayName: String?
    let learnUrl: String?

    // MARK: - Feature flags (from community_types.feature_flags JSONB)

    let featureFlags: [String: Bool]

    // MARK: - Geography (from communities.geography JSONB)

    let geography: CommunityGeography

    // MARK: - Flag accessor with xcconfig fallback

    /// Returns the backend flag value if present, otherwise falls back to
    /// the compile-time xcconfig value via `readFeatureFlag(_:)`.
    func flag(_ key: String) -> Bool {
        featureFlags[key] ?? readFeatureFlag(key)
    }

    // MARK: - Resolved branding with xcconfig fallback

    var resolvedLogoAssetName: String {
        if let name = logoAssetName, !name.isEmpty { return name }
        return AppEnvironment.shared.appLogoAsset
    }

    var resolvedTagline: String {
        if let t = tagline, !t.isEmpty { return t }
        return AppEnvironment.shared.communityTagline
    }

    var resolvedDisplayName: String {
        if let d = displayName, !d.isEmpty { return d }
        return AppEnvironment.shared.appDisplayName
    }

    // MARK: - Resolved learn URL (falls back to xcconfig DEFAULT_LEARN_URL)

    var resolvedLearnUrl: String {
        if let u = learnUrl, !u.isEmpty { return u }
        return AppEnvironment.shared.defaultLearnURL
    }

    // MARK: - Resolved geography (no xcconfig fallback — empty means not configured)

    var resolvedDefaultRiver: String? {
        if let r = geography.defaultRiver, !r.isEmpty { return r }
        return nil
    }

    var resolvedLodgeRivers: [String] {
        geography.lodgeRivers ?? []
    }

    var resolvedDefaultWaterBody: String? {
        if let w = geography.defaultWaterBody, !w.isEmpty { return w }
        return nil
    }

    var resolvedLodgeWaterBodies: [String] {
        geography.lodgeWaterBodies ?? []
    }

    var resolvedForecastLocation: String? {
        if let f = geography.forecastLocation, !f.isEmpty { return f }
        return nil
    }

    var resolvedDefaultMapLatitude: Double? {
        geography.defaultMapLatitude
    }

    /// True when the community has no geography configured on the backend
    var hasGeography: Bool {
        !resolvedLodgeRivers.isEmpty || resolvedForecastLocation != nil
    }

    var resolvedDefaultMapLongitude: Double? {
        geography.defaultMapLongitude
    }

    // MARK: - Default (falls through entirely to xcconfig)

    static let `default` = CommunityConfig(
        logoUrl: nil,
        logoAssetName: nil,
        tagline: nil,
        displayName: nil,
        learnUrl: nil,
        featureFlags: [:],
        geography: .empty
    )
}
