import XCTest
@testable import SkeenaSystem

/// Tests for CommunityConfig — verifies the flag fallback chain,
/// branding resolution, JSON decoding, and the CommunityInfo.config merge.
final class CommunityConfigTests: XCTestCase {

    // MARK: - Flag Fallback Chain

    func testFlag_returnsBackendValue_whenPresent() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: ["FF_TEST_FLAG": true],
            geography: .empty
        )
        XCTAssertTrue(config.flag("FF_TEST_FLAG"),
                      "Should return backend value when key is present")
    }

    func testFlag_returnsBackendFalse_whenExplicitlyFalse() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: ["FF_TEST_FLAG": false],
            geography: .empty
        )
        XCTAssertFalse(config.flag("FF_TEST_FLAG"),
                       "Should return false when backend explicitly sets it to false")
    }

    func testFlag_fallsBackToXcconfig_whenKeyAbsent() {
        let config = CommunityConfig.default
        // FF_CATCH_CAROUSEL is true in DevTEST xcconfig
        let xcconfigValue = readFeatureFlag("FF_CATCH_CAROUSEL")
        XCTAssertEqual(config.flag("FF_CATCH_CAROUSEL"), xcconfigValue,
                       "Should fall back to xcconfig when key absent from backend")
    }

    func testFlag_returnsFalse_whenKeyAbsentFromBothSources() {
        let config = CommunityConfig.default
        XCTAssertFalse(config.flag("FF_NONEXISTENT_12345"),
                       "Should return false when key absent from both backend and xcconfig")
    }

    func testFlag_backendOverridesXcconfig() {
        // FF_CATCH_CAROUSEL is true in DevTEST xcconfig — backend overrides to false
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: ["FF_CATCH_CAROUSEL": false],
            geography: .empty
        )
        XCTAssertFalse(config.flag("FF_CATCH_CAROUSEL"),
                       "Backend value should override xcconfig value")
    }

    // MARK: - Branding Resolution

    func testResolvedLogoAssetName_returnsBackendValue_whenPresent() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: "BendFlyShopLogo", tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: [:],
            geography: .empty
        )
        XCTAssertEqual(config.resolvedLogoAssetName, "BendFlyShopLogo")
    }

    func testResolvedLogoAssetName_fallsBackToXcconfig_whenNil() {
        let config = CommunityConfig.default
        XCTAssertEqual(config.resolvedLogoAssetName, AppEnvironment.shared.appLogoAsset,
                       "Should fall back to xcconfig APP_LOGO_ASSET")
    }

    func testResolvedLogoAssetName_fallsBackToXcconfig_whenEmpty() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: "", tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: [:],
            geography: .empty
        )
        XCTAssertEqual(config.resolvedLogoAssetName, AppEnvironment.shared.appLogoAsset,
                       "Should fall back to xcconfig when asset name is empty string")
    }

    func testResolvedDisplayName_returnsBackendValue_whenPresent() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: "Custom Name", learnUrl: nil,
            featureFlags: [:],
            geography: .empty
        )
        XCTAssertEqual(config.resolvedDisplayName, "Custom Name")
    }

    func testResolvedDisplayName_fallsBackToXcconfig_whenNil() {
        let config = CommunityConfig.default
        XCTAssertEqual(config.resolvedDisplayName, AppEnvironment.shared.appDisplayName)
    }

    func testResolvedTagline_returnsBackendValue_whenPresent() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: "Custom Tagline", displayName: nil, learnUrl: nil,
            featureFlags: [:],
            geography: .empty
        )
        XCTAssertEqual(config.resolvedTagline, "Custom Tagline")
    }

    // MARK: - Default Config

    func testDefault_hasEmptyFeatureFlags() {
        XCTAssertTrue(CommunityConfig.default.featureFlags.isEmpty,
                      "Default config should have no backend flags")
    }

    func testDefault_hasNilBranding() {
        let d = CommunityConfig.default
        XCTAssertNil(d.logoUrl)
        XCTAssertNil(d.logoAssetName)
        XCTAssertNil(d.tagline)
        XCTAssertNil(d.displayName)
    }

    // MARK: - JSON Decoding

    func testDecoding_fullConfig() throws {
        let json = """
        {
            "logoUrl": "https://example.com/logo.png",
            "logoAssetName": "TestLogo",
            "tagline": "Test Tagline",
            "displayName": "Test Community",
            "learnUrl": "https://example.com/learn",
            "featureFlags": {"FF_MEET_STAFF": true, "FF_FLIGHT_INFO": false},
            "geography": {"default_river": "Hoh River", "lodge_rivers": ["Hoh River", "Green River"], "forecast_location": "Western Washington"}
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(CommunityConfig.self, from: json)

        XCTAssertEqual(config.logoUrl, "https://example.com/logo.png")
        XCTAssertEqual(config.logoAssetName, "TestLogo")
        XCTAssertEqual(config.tagline, "Test Tagline")
        XCTAssertEqual(config.displayName, "Test Community")
        XCTAssertEqual(config.learnUrl, "https://example.com/learn")
        XCTAssertEqual(config.featureFlags["FF_MEET_STAFF"], true)
        XCTAssertEqual(config.featureFlags["FF_FLIGHT_INFO"], false)
        XCTAssertEqual(config.featureFlags.count, 2)
    }

    func testDecoding_roundtrip() throws {
        let original = CommunityConfig(
            logoUrl: "https://example.com/logo.png",
            logoAssetName: "TestLogo",
            tagline: "Tagline",
            displayName: "Name",
            learnUrl: "https://example.com/learn",
            featureFlags: ["FF_A": true, "FF_B": false],
            geography: CommunityGeography(
                defaultRiver: "Hoh River", lodgeRivers: ["Hoh River"],
                defaultWaterBody: "Puget Sound", lodgeWaterBodies: ["Puget Sound"],
                forecastLocation: "Western WA", defaultMapLatitude: 47.9, defaultMapLongitude: -122.8
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommunityConfig.self, from: data)

        XCTAssertEqual(original, decoded, "Encode/decode roundtrip should produce equal config")
    }

    // MARK: - CommunityInfo.config Merge

    func testCommunityInfo_config_mergesBrandingAndFlags() {
        let typeInfo = CommunityTypeInfo(
            id: "type-1",
            name: "Lodge",
            featureFlags: ["FF_MEET_STAFF": true, "FF_FLIGHT_INFO": false]
        )

        let communityInfo = CommunityInfo(
            id: "comm-1",
            name: "Test Lodge",
            code: "ABC123",
            isActive: true,
            communityTypeId: "type-1",
            logoUrl: "https://example.com/logo.png",
            logoAssetName: "TestLogo",
            tagline: "Welcome",
            displayName: "Test Lodge Display",
            learnUrl: nil,
            geography: CommunityGeography(
                defaultRiver: "Hoh River", lodgeRivers: ["Hoh River", "Green River"],
                defaultWaterBody: nil, lodgeWaterBodies: nil,
                forecastLocation: "Western WA", defaultMapLatitude: 47.9, defaultMapLongitude: -122.8
            ),
            communityTypes: typeInfo
        )

        let config = communityInfo.config

        // Branding from community
        XCTAssertEqual(config.logoUrl, "https://example.com/logo.png")
        XCTAssertEqual(config.logoAssetName, "TestLogo")
        XCTAssertEqual(config.tagline, "Welcome")
        XCTAssertEqual(config.displayName, "Test Lodge Display")

        // Flags from type
        XCTAssertTrue(config.flag("FF_MEET_STAFF"))
        XCTAssertFalse(config.flag("FF_FLIGHT_INFO"))
    }

    func testCommunityInfo_config_withNilType_returnsEmptyFlags() {
        let communityInfo = CommunityInfo(
            id: "comm-1",
            name: "Test",
            code: "ABC123",
            isActive: true,
            communityTypeId: nil,
            logoUrl: nil,
            logoAssetName: nil,
            tagline: nil,
            displayName: nil,
            learnUrl: nil,
            geography: nil,
            communityTypes: nil
        )

        let config = communityInfo.config

        XCTAssertTrue(config.featureFlags.isEmpty,
                      "Config should have empty flags when community has no type")
    }

    // MARK: - Equatable

    func testEquatable_sameValues_areEqual() {
        let a = CommunityConfig(
            logoUrl: "url", logoAssetName: "asset", tagline: "tag", displayName: "name", learnUrl: nil,
            featureFlags: ["FF_A": true], geography: .empty
        )
        let b = CommunityConfig(
            logoUrl: "url", logoAssetName: "asset", tagline: "tag", displayName: "name", learnUrl: nil,
            featureFlags: ["FF_A": true], geography: .empty
        )
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentFlags_areNotEqual() {
        let a = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: ["FF_A": true], geography: .empty
        )
        let b = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: ["FF_A": false], geography: .empty
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Geography Resolution

    func testResolvedGeography_returnsBackendValues_whenPresent() {
        let geo = CommunityGeography(
            defaultRiver: "Skeena River",
            lodgeRivers: ["Skeena River", "Kispiox River"],
            defaultWaterBody: "Pacific Ocean",
            lodgeWaterBodies: ["Pacific Ocean"],
            forecastLocation: "Northern BC",
            defaultMapLatitude: 54.5,
            defaultMapLongitude: -128.6
        )
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: [:], geography: geo
        )

        XCTAssertEqual(config.resolvedDefaultRiver, "Skeena River")
        XCTAssertEqual(config.resolvedLodgeRivers, ["Skeena River", "Kispiox River"])
        XCTAssertEqual(config.resolvedDefaultWaterBody, "Pacific Ocean")
        XCTAssertEqual(config.resolvedLodgeWaterBodies, ["Pacific Ocean"])
        XCTAssertEqual(config.resolvedForecastLocation, "Northern BC")
        XCTAssertEqual(config.resolvedDefaultMapLatitude, 54.5)
        XCTAssertEqual(config.resolvedDefaultMapLongitude, -128.6)
    }

    func testResolvedGeography_returnsNilAndEmpty_whenNotConfigured() {
        let config = CommunityConfig.default

        XCTAssertNil(config.resolvedDefaultRiver, "Should be nil when no geography configured")
        XCTAssertTrue(config.resolvedLodgeRivers.isEmpty, "Should be empty when no geography configured")
        XCTAssertNil(config.resolvedForecastLocation, "Should be nil when no geography configured")
        XCTAssertNil(config.resolvedDefaultMapLatitude, "Should be nil when no geography configured")
        XCTAssertNil(config.resolvedDefaultMapLongitude, "Should be nil when no geography configured")
        XCTAssertFalse(config.hasGeography, "hasGeography should be false when nothing configured")
    }

    func testHasGeography_trueWhenRiversConfigured() {
        let geo = CommunityGeography(
            defaultRiver: nil, lodgeRivers: ["Test River"],
            defaultWaterBody: nil, lodgeWaterBodies: nil,
            forecastLocation: nil, defaultMapLatitude: nil, defaultMapLongitude: nil
        )
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: [:], geography: geo
        )
        XCTAssertTrue(config.hasGeography)
    }

    // MARK: - Learn URL Resolution

    func testResolvedLearnUrl_returnsBackendValue_whenPresent() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil,
            learnUrl: "https://community.example.com/learn",
            featureFlags: [:], geography: .empty
        )
        XCTAssertEqual(config.resolvedLearnUrl, "https://community.example.com/learn")
    }

    func testResolvedLearnUrl_fallsBackToXcconfig_whenNil() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: nil,
            featureFlags: [:], geography: .empty
        )
        XCTAssertEqual(config.resolvedLearnUrl, AppEnvironment.shared.defaultLearnURL,
                       "Should fall back to xcconfig DEFAULT_LEARN_URL when learnUrl is nil")
    }

    func testResolvedLearnUrl_fallsBackToXcconfig_whenEmpty() {
        let config = CommunityConfig(
            logoUrl: nil, logoAssetName: nil, tagline: nil, displayName: nil, learnUrl: "",
            featureFlags: [:], geography: .empty
        )
        XCTAssertEqual(config.resolvedLearnUrl, AppEnvironment.shared.defaultLearnURL,
                       "Should fall back to xcconfig DEFAULT_LEARN_URL when learnUrl is empty string")
    }

    func testCommunityInfo_config_passesLearnUrlThrough() {
        let communityInfo = CommunityInfo(
            id: "comm-1",
            name: "Test",
            code: "TST001",
            isActive: true,
            communityTypeId: nil,
            logoUrl: nil,
            logoAssetName: nil,
            tagline: nil,
            displayName: nil,
            learnUrl: "https://custom.example.com/tutorials",
            geography: nil,
            communityTypes: nil
        )
        XCTAssertEqual(communityInfo.config.resolvedLearnUrl, "https://custom.example.com/tutorials")
    }
}
