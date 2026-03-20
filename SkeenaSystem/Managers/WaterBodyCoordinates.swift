//
//  WaterBodyCoordinates.swift
//  SkeenaSystem
//
//  Global water body atlas — polygon geofence data for bays, sounds, canals, etc.
//  Add new water bodies here as they're onboarded; never remove existing entries.
//  The active set for each app instance is controlled by LODGE_WATER_BODIES in xcconfig.
//
//  Polygons are simplified (~15–30 vertices) and ordered clockwise.
//  Close each polygon by connecting the last point back to the first.
//

import CoreLocation

/// Central atlas of water body polygon data keyed by name (e.g. "Puget Sound").
/// WaterBodyLocator reads from this atlas, filtered by the community's config.
enum WaterBodyAtlas {

    /// Recommended check order: more specific/smaller areas first, then larger.
    /// This prevents a point in Hood Canal from matching "Puget Sound" first.
    static let checkOrder: [String] = [
        "Hood Canal",
        "Puget Sound",
        // Add new entries here in specificity order (most specific first)
    ]

    /// Master dictionary: key = water body name (must match LODGE_WATER_BODIES in xcconfig),
    /// value = clockwise polygon vertices.
    static let all: [String: [CLLocationCoordinate2D]] = [

        // ─────────────────────────────────────────────
        // Washington State — Puget Sound Region
        // ─────────────────────────────────────────────

        "Puget Sound": [
            // Simplified outer boundary, clockwise from NW
            // --- North (Admiralty Inlet / Possession Sound) ---
            CLLocationCoordinate2D(latitude: 48.170, longitude: -122.760),  // Point Wilson, Port Townsend
            CLLocationCoordinate2D(latitude: 48.160, longitude: -122.680),  // Admiralty Head, Whidbey
            CLLocationCoordinate2D(latitude: 48.030, longitude: -122.550),  // Double Bluff, Whidbey S
            CLLocationCoordinate2D(latitude: 47.905, longitude: -122.384),  // Possession Point, Whidbey S tip
            // --- East shore (going south) ---
            CLLocationCoordinate2D(latitude: 47.977, longitude: -122.224),  // Everett waterfront
            CLLocationCoordinate2D(latitude: 47.948, longitude: -122.305),  // Mukilteo
            CLLocationCoordinate2D(latitude: 47.811, longitude: -122.383),  // Edmonds
            CLLocationCoordinate2D(latitude: 47.694, longitude: -122.400),  // Shilshole Bay
            CLLocationCoordinate2D(latitude: 47.625, longitude: -122.387),  // Magnolia Bluff
            CLLocationCoordinate2D(latitude: 47.605, longitude: -122.338),  // Seattle waterfront / Pier 91
            CLLocationCoordinate2D(latitude: 47.576, longitude: -122.352),  // Harbor Island
            CLLocationCoordinate2D(latitude: 47.570, longitude: -122.421),  // Alki Point
            CLLocationCoordinate2D(latitude: 47.530, longitude: -122.400),  // Lincoln Park
            CLLocationCoordinate2D(latitude: 47.461, longitude: -122.383),  // Three Tree Point
            CLLocationCoordinate2D(latitude: 47.388, longitude: -122.370),  // Dash Point area
            CLLocationCoordinate2D(latitude: 47.310, longitude: -122.395),  // Federal Way shoreline
            CLLocationCoordinate2D(latitude: 47.285, longitude: -122.422),  // Tacoma, Commencement Bay
            // --- South (Tacoma Narrows) ---
            CLLocationCoordinate2D(latitude: 47.270, longitude: -122.548),  // Tacoma Narrows east
            CLLocationCoordinate2D(latitude: 47.270, longitude: -122.560),  // Tacoma Narrows west
            // --- West shore (going north) ---
            CLLocationCoordinate2D(latitude: 47.305, longitude: -122.533),  // Point Defiance
            CLLocationCoordinate2D(latitude: 47.335, longitude: -122.582),  // Gig Harbor area
            CLLocationCoordinate2D(latitude: 47.430, longitude: -122.555),  // Olalla
            CLLocationCoordinate2D(latitude: 47.530, longitude: -122.540),  // Manchester
            CLLocationCoordinate2D(latitude: 47.563, longitude: -122.625),  // Bremerton
            CLLocationCoordinate2D(latitude: 47.650, longitude: -122.573),  // Brownsville
            CLLocationCoordinate2D(latitude: 47.700, longitude: -122.560),  // Agate Passage area
            CLLocationCoordinate2D(latitude: 47.730, longitude: -122.553),  // Suquamish
            CLLocationCoordinate2D(latitude: 47.796, longitude: -122.497),  // Kingston
            CLLocationCoordinate2D(latitude: 47.912, longitude: -122.527),  // Point No Point
            CLLocationCoordinate2D(latitude: 47.930, longitude: -122.620),  // Foulweather Bluff
            CLLocationCoordinate2D(latitude: 48.030, longitude: -122.760),  // Marrowstone Point area
        ],

        "Hood Canal": [
            // East shore south, then west shore north, clockwise
            // --- North entrance ---
            CLLocationCoordinate2D(latitude: 47.930, longitude: -122.620),  // Foulweather Bluff (east side)
            CLLocationCoordinate2D(latitude: 47.910, longitude: -122.660),  // Tala Point (west side)
            // --- West shore (Olympic/Jefferson side, going south) ---
            CLLocationCoordinate2D(latitude: 47.850, longitude: -122.700),  // Shine area
            CLLocationCoordinate2D(latitude: 47.760, longitude: -122.755),  // Coyle
            CLLocationCoordinate2D(latitude: 47.660, longitude: -122.850),  // Pleasant Harbor
            CLLocationCoordinate2D(latitude: 47.560, longitude: -122.900),  // Eldon
            CLLocationCoordinate2D(latitude: 47.480, longitude: -122.940),  // Lilliwaup
            CLLocationCoordinate2D(latitude: 47.410, longitude: -122.960),  // Hoodsport
            CLLocationCoordinate2D(latitude: 47.365, longitude: -122.930),  // Potlatch area
            CLLocationCoordinate2D(latitude: 47.340, longitude: -122.880),  // Union / Great Bend south
            // --- Hook (turning east/northeast toward Belfair) ---
            CLLocationCoordinate2D(latitude: 47.370, longitude: -122.830),  // Lynch Cove
            CLLocationCoordinate2D(latitude: 47.427, longitude: -122.795),  // Belfair (south tip of hook)
            // --- East shore (Kitsap side, going north) ---
            CLLocationCoordinate2D(latitude: 47.445, longitude: -122.860),  // Dewatto
            CLLocationCoordinate2D(latitude: 47.530, longitude: -122.870),  // Holly
            CLLocationCoordinate2D(latitude: 47.630, longitude: -122.830),  // Seabeck
            CLLocationCoordinate2D(latitude: 47.748, longitude: -122.727),  // Bangor (NOAA station)
            CLLocationCoordinate2D(latitude: 47.820, longitude: -122.680),  // Lofall
            CLLocationCoordinate2D(latitude: 47.890, longitude: -122.640),  // Vinland
            CLLocationCoordinate2D(latitude: 47.928, longitude: -122.618),  // Near Foulweather Bluff
        ],

        // ─────────────────────────────────────────────
        // Add new water bodies below this line.
        // Key must match the name in LODGE_WATER_BODIES xcconfig.
        // ─────────────────────────────────────────────
    ]
}
