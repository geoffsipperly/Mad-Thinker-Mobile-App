import Foundation
@testable import SkeenaSystem

/// Sets up CommunityService with geography from the xcconfig (AppEnvironment)
/// so that geography-dependent tests (RiverLocator, WaterBodyLocator, etc.)
/// work in the test environment where there's no active community.
@MainActor
enum TestGeographySetup {
    static func injectXcconfigGeography() {
        let env = AppEnvironment.shared
        let geo = CommunityGeography(
            defaultRiver: env.defaultRiver,
            lodgeRivers: env.lodgeRivers,
            defaultWaterBody: env.defaultWaterBody,
            lodgeWaterBodies: env.lodgeWaterBodies,
            forecastLocation: env.forecastLocation,
            defaultMapLatitude: env.defaultMapLatitude,
            defaultMapLongitude: env.defaultMapLongitude
        )
        let config = CommunityConfig(
            logoUrl: nil,
            logoAssetName: nil,
            tagline: nil,
            displayName: nil,
            learnUrl: nil,
            featureFlags: [:],
            geography: geo
        )
        CommunityService.shared.setTestConfig(config)
    }

    static func clearConfig() {
        CommunityService.shared.setTestConfig(.default)
    }
}
