//
//  RiverCoordinates.swift
//  SkeenaSystem
//
//  Global river atlas — GPS spine data for all communities.
//  Add new rivers here as they're onboarded; never remove existing entries.
//  The active set for each app instance is controlled by LODGE_RIVERS in xcconfig.
//

import CoreLocation

/// Central atlas of river GPS spine data keyed by full river name (e.g. "Nehalem River").
/// RiverLocator reads from this atlas, filtered by the community's `lodgeRivers` config.
enum RiverAtlas {

    /// Master dictionary: key = full river name (must match LODGE_RIVERS in xcconfig),
    /// value = ordered array of spine coordinates from mouth → headwaters.
    static let all: [String: [CLLocationCoordinate2D]] = [

        // ─────────────────────────────────────────────
        // Oregon Coast — Tillamook / Bend Fly Shop
        // ─────────────────────────────────────────────

        "Nehalem River": [
            // Mile 0 — Nehalem Bay mouth at the Pacific coast
            CLLocationCoordinate2D(latitude: 45.6580, longitude: -123.9348),
            // Mile 5 — Near Wheeler / Hwy 101 bridge
            CLLocationCoordinate2D(latitude: 45.7010, longitude: -123.8860),
            // Mile 10 — Between Mohler and Nehalem Falls (upper tidal zone)
            CLLocationCoordinate2D(latitude: 45.7150, longitude: -123.8300),
            // Mile 15 — Nehalem Falls area
            CLLocationCoordinate2D(latitude: 45.7267, longitude: -123.7719),
            // Mile 20 — Near Salmonberry River confluence
            CLLocationCoordinate2D(latitude: 45.7450, longitude: -123.7000),
            // Mile 25 — Between Salmonberry and Spruce Run
            CLLocationCoordinate2D(latitude: 45.7750, longitude: -123.6500),
            // Mile 30 — Near Henry Rierson Spruce Run Campground
            CLLocationCoordinate2D(latitude: 45.8126, longitude: -123.6117),
            // Mile 35 — Between Spruce Run and Grand Rapids
            CLLocationCoordinate2D(latitude: 45.8550, longitude: -123.5600),
            // Mile 40 — Approaching Grand Rapids (near Hwy 26/103)
            CLLocationCoordinate2D(latitude: 45.8900, longitude: -123.5150),
            // Mile 45 — Grand Rapids
            CLLocationCoordinate2D(latitude: 45.9010, longitude: -123.5040),
        ],

        "Wilson River": [
            // Mile 0 — Mouth at Tillamook Bay
            CLLocationCoordinate2D(latitude: 45.4790, longitude: -123.8901),
            // Mile 5 — Sollie Smith Boat Launch area, lower river
            CLLocationCoordinate2D(latitude: 45.4775, longitude: -123.8075),
            // Mile 10 — USGS gauge / Mills Bridge area (Hwy 6)
            CLLocationCoordinate2D(latitude: 45.4760, longitude: -123.7250),
            // Mile 15 — Mid-river, entering Tillamook State Forest
            CLLocationCoordinate2D(latitude: 45.4900, longitude: -123.6500),
            // Mile 20 — Jones Creek Campground area (Hwy 6 MP 22)
            CLLocationCoordinate2D(latitude: 45.5500, longitude: -123.5800),
            // Mile 25 — Elk Creek Campground / Wilson River Trail
            CLLocationCoordinate2D(latitude: 45.5900, longitude: -123.5100),
            // Mile 30 — Upper river, approaching headwaters
            CLLocationCoordinate2D(latitude: 45.6090, longitude: -123.4670),
        ],

        "Trask River": [
            // Mile 0 — Mouth at Tillamook Bay (near Memaloose Point)
            CLLocationCoordinate2D(latitude: 45.4704, longitude: -123.8826),
            // Mile 5 — Between Steiner and Loren's Drift launches
            CLLocationCoordinate2D(latitude: 45.4310, longitude: -123.8000),
            // Mile 10 — USGS gauge above Cedar Creek
            CLLocationCoordinate2D(latitude: 45.4462, longitude: -123.7104),
            // Mile 15 — Upper main stem, approaching fork confluence
            CLLocationCoordinate2D(latitude: 45.4420, longitude: -123.6400),
            // Mile 18 — North Fork / South Fork confluence
            CLLocationCoordinate2D(latitude: 45.4398, longitude: -123.6115),
            // Mile 25 — North Fork, mid-reach in Tillamook State Forest
            CLLocationCoordinate2D(latitude: 45.4600, longitude: -123.5500),
            // Mile 30 — North Fork, upper forest
            CLLocationCoordinate2D(latitude: 45.4800, longitude: -123.5000),
            // Mile 35 — North Fork headwaters area
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -123.4500),
        ],

        "Nestucca River": [
            // Mile 0 — Mouth at Nestucca Bay (Pacific City)
            CLLocationCoordinate2D(latitude: 45.1843, longitude: -123.9573),
            // Mile 5 — Lower river, above Pacific City
            CLLocationCoordinate2D(latitude: 45.2100, longitude: -123.9400),
            // Mile 10 — Three Rivers / Hebo area (near Hwy 101)
            CLLocationCoordinate2D(latitude: 45.2350, longitude: -123.8750),
            // Mile 15 — Between Hebo and Beaver
            CLLocationCoordinate2D(latitude: 45.2550, longitude: -123.8400),
            // Mile 20 — Beaver / Bixby Boat Launch area
            CLLocationCoordinate2D(latitude: 45.2730, longitude: -123.8340),
            // Mile 25 — Upstream of Beaver, BLM Nestucca Backcountry Byway
            CLLocationCoordinate2D(latitude: 45.2900, longitude: -123.7800),
            // Mile 30 — Blaine area, mid-river
            CLLocationCoordinate2D(latitude: 45.3000, longitude: -123.7200),
            // Mile 35 — Upper Nestucca, National Forest land
            CLLocationCoordinate2D(latitude: 45.3050, longitude: -123.6500),
            // Mile 40 — Approaching Yamhill County line
            CLLocationCoordinate2D(latitude: 45.3100, longitude: -123.5800),
            // Mile 45 — Upper river valley
            CLLocationCoordinate2D(latitude: 45.3180, longitude: -123.5100),
            // Mile 50 — Near USGS gauge / McMinnville headwaters area
            CLLocationCoordinate2D(latitude: 45.3248, longitude: -123.4512),
        ],

        "Kilchis River": [
            // Mile 0 — Mouth at Tillamook Bay (Idaville)
            CLLocationCoordinate2D(latitude: 45.4962, longitude: -123.8648),
            // Mile 5 — Mapes Creek / Logger Bridge area
            CLLocationCoordinate2D(latitude: 45.5200, longitude: -123.8280),
            // Mile 10 — Kilchis River County Campground
            CLLocationCoordinate2D(latitude: 45.5390, longitude: -123.7840),
            // Mile 15 — Upper river, North/South Fork confluence area
            CLLocationCoordinate2D(latitude: 45.5550, longitude: -123.7500),
        ],

        // ─────────────────────────────────────────────
        // Add new community rivers below this line.
        // Key must match the full name in LODGE_RIVERS xcconfig
        // (e.g. "Hoh River", "Bogachiel River").
        // ─────────────────────────────────────────────

        "Hoh River": [
            // Mile 0 — River mouth at Pacific Ocean, Hoh Indian Reservation (Verified — GNIS)
            CLLocationCoordinate2D(latitude: 47.7494, longitude: -124.4401),
            // Mile 5 — Lower Hoh valley, between USGS Mile 4.3 and Mile 8.9 stations (Interpolated)
            CLLocationCoordinate2D(latitude: 47.7399, longitude: -124.3598),
            // Mile 10 — Lower-middle Hoh valley, downstream of US Highway 101 (Interpolated)
            CLLocationCoordinate2D(latitude: 47.7698, longitude: -124.3044),
            // Mile 15 — Near US Highway 101 bridge crossing (Verified — USGS 12041200)
            CLLocationCoordinate2D(latitude: 47.8069, longitude: -124.2497),
            // Mile 20 — Middle Hoh valley, near Willoughby Creek confluence (Verified — USGS 12041100)
            CLLocationCoordinate2D(latitude: 47.8217, longitude: -124.1941),
            // Mile 25 — Upper-middle Hoh valley (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8121, longitude: -124.1131),
            // Mile 30 — Near South Fork Hoh confluence, approaching Olympic NP boundary (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8155, longitude: -124.0480),
            // Mile 35 — Olympic National Park, Hoh Rain Forest, above South Fork (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8444, longitude: -123.9551),
            // Mile 40 — Hoh Rain Forest, above Visitor Center area (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8460, longitude: -123.8892),
            // Mile 45 — Upper Hoh valley, approaching Olympus Guard Station (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8279, longitude: -123.8355),
            // Mile 50 — Upper Hoh valley, approaching Glacier Meadows (Interpolated)
            CLLocationCoordinate2D(latitude: 47.8098, longitude: -123.7818),
            // Mile 55 — Near Hoh Glacier terminus, headwaters on Mount Olympus (Interpolated)
            CLLocationCoordinate2D(latitude: 47.7918, longitude: -123.7280),
        ],

        "Sauk River": [
            // Mile 0 — Mouth at Skagit River confluence, Rockport (V — GNIS)
            CLLocationCoordinate2D(latitude: 48.4850, longitude: -121.5920),
            // Mile 5 — Lower Sauk, south of Rockport
            CLLocationCoordinate2D(latitude: 48.4500, longitude: -121.5750),
            // Mile 10 — Near USGS 12189500 gauge (V)
            CLLocationCoordinate2D(latitude: 48.4246, longitude: -121.5685),
            // Mile 15 — Between Sauk and Darrington
            CLLocationCoordinate2D(latitude: 48.3700, longitude: -121.5750),
            // Mile 20 — Approaching Darrington
            CLLocationCoordinate2D(latitude: 48.3100, longitude: -121.5900),
            // Mile 25 — Near Darrington (V — town GPS)
            CLLocationCoordinate2D(latitude: 48.2540, longitude: -121.6020),
            // Mile 30 — South of Darrington, above White Chuck River confluence
            CLLocationCoordinate2D(latitude: 48.2000, longitude: -121.5200),
            // Mile 35 — Near USGS 12186000, above Whitechuck River (V)
            CLLocationCoordinate2D(latitude: 48.1687, longitude: -121.4707),
            // Mile 40 — Between Whitechuck and forks
            CLLocationCoordinate2D(latitude: 48.1200, longitude: -121.4100),
            // Mile 45 — Near North/South Fork confluence, headwaters area (V — GNIS)
            CLLocationCoordinate2D(latitude: 48.0900, longitude: -121.3800),
        ],

        "Skykomish River": [
            // Mile 0 — Mouth at Snoqualmie River confluence, Monroe (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.8554, longitude: -121.9690),
            // Mile 5 — Between Monroe and Sultan
            CLLocationCoordinate2D(latitude: 47.8580, longitude: -121.9000),
            // Mile 10 — Near Sultan (V — town GPS)
            CLLocationCoordinate2D(latitude: 47.8620, longitude: -121.8130),
            // Mile 15 — Between Sultan and Gold Bar
            CLLocationCoordinate2D(latitude: 47.8500, longitude: -121.7400),
            // Mile 20 — Near Gold Bar, USGS 12134500 (V)
            CLLocationCoordinate2D(latitude: 47.8375, longitude: -121.6656),
            // Mile 25 — Between Gold Bar and Index
            CLLocationCoordinate2D(latitude: 47.8280, longitude: -121.5900),
            // Mile 30 — Near Index, North/South Fork confluence (V — town GPS)
            CLLocationCoordinate2D(latitude: 47.8200, longitude: -121.5600),
            // Mile 35 — South Fork, between Index and Skykomish
            CLLocationCoordinate2D(latitude: 47.7900, longitude: -121.4800),
            // Mile 40 — Between Index and Skykomish town
            CLLocationCoordinate2D(latitude: 47.7500, longitude: -121.4000),
            // Mile 45 — Near Skykomish town (V — town GPS)
            CLLocationCoordinate2D(latitude: 47.7100, longitude: -121.3500),
            // Mile 50 — Tye River, Deception Falls area
            CLLocationCoordinate2D(latitude: 47.7180, longitude: -121.2400),
            // Mile 55 — Upper Tye River valley
            CLLocationCoordinate2D(latitude: 47.7300, longitude: -121.1500),
            // Mile 60 — Near Stevens Pass, headwaters (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.7470, longitude: -121.0890),
        ],

        "Green River": [
            // Mile 0 — Duwamish River mouth at Elliott Bay, Seattle (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.5650, longitude: -122.3450),
            // Mile 5 — Lower Duwamish Waterway
            CLLocationCoordinate2D(latitude: 47.5350, longitude: -122.3250),
            // Mile 10 — Tukwila area, Green/Duwamish name transition
            CLLocationCoordinate2D(latitude: 47.4750, longitude: -122.2700),
            // Mile 15 — Renton area
            CLLocationCoordinate2D(latitude: 47.4400, longitude: -122.2500),
            // Mile 20 — Kent area
            CLLocationCoordinate2D(latitude: 47.3900, longitude: -122.2400),
            // Mile 25 — Between Kent and Auburn
            CLLocationCoordinate2D(latitude: 47.3500, longitude: -122.2200),
            // Mile 30 — Near Auburn, USGS 12113000 at RM 32 (V)
            CLLocationCoordinate2D(latitude: 47.3125, longitude: -122.2028),
            // Mile 35 — Flaming Geyser State Park area
            CLLocationCoordinate2D(latitude: 47.3000, longitude: -122.1300),
            // Mile 40 — Near Black Diamond
            CLLocationCoordinate2D(latitude: 47.3100, longitude: -122.0200),
            // Mile 45 — Green River Gorge
            CLLocationCoordinate2D(latitude: 47.3200, longitude: -121.9300),
            // Mile 50 — Palmer / Kanaskat-Palmer State Park area
            CLLocationCoordinate2D(latitude: 47.3200, longitude: -121.8600),
            // Mile 55 — Eagle Gorge area
            CLLocationCoordinate2D(latitude: 47.3300, longitude: -121.7800),
            // Mile 60 — Approaching Howard Hanson Dam
            CLLocationCoordinate2D(latitude: 47.3350, longitude: -121.7200),
            // Mile 65 — Howard Hanson Dam (V — USGS 12105900)
            CLLocationCoordinate2D(latitude: 47.3278, longitude: -121.6742),
            // Mile 70 — Upper Green River above dam
            CLLocationCoordinate2D(latitude: 47.3200, longitude: -121.5800),
            // Mile 75 — Headwaters area, near Blowout Creek / Stampede Pass (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.3100, longitude: -121.4800),
        ],

        "Cowlitz River": [
            // Mile 0 — Mouth at Columbia River, Longview/Kelso (V — GNIS)
            CLLocationCoordinate2D(latitude: 46.1050, longitude: -122.9550),
            // Mile 5 — Lower Cowlitz valley
            CLLocationCoordinate2D(latitude: 46.1400, longitude: -122.9400),
            // Mile 10 — Approaching Castle Rock
            CLLocationCoordinate2D(latitude: 46.2100, longitude: -122.9300),
            // Mile 15 — Near Castle Rock, USGS 14243000 at RM 17.3 (V)
            CLLocationCoordinate2D(latitude: 46.2748, longitude: -122.9146),
            // Mile 20 — Above Castle Rock
            CLLocationCoordinate2D(latitude: 46.3100, longitude: -122.8800),
            // Mile 25 — Near Toutle River confluence
            CLLocationCoordinate2D(latitude: 46.3500, longitude: -122.8400),
            // Mile 30 — Near Toledo
            CLLocationCoordinate2D(latitude: 46.4100, longitude: -122.8000),
            // Mile 35 — Between Toledo and Mayfield Dam
            CLLocationCoordinate2D(latitude: 46.4500, longitude: -122.7200),
            // Mile 40 — Mayfield Dam area (V — USGS 14238000)
            CLLocationCoordinate2D(latitude: 46.5104, longitude: -122.6162),
            // Mile 45 — Mayfield Lake
            CLLocationCoordinate2D(latitude: 46.5200, longitude: -122.5500),
            // Mile 50 — Mossyrock Dam area
            CLLocationCoordinate2D(latitude: 46.5300, longitude: -122.4700),
            // Mile 55 — Lower Riffe Lake
            CLLocationCoordinate2D(latitude: 46.5350, longitude: -122.3800),
            // Mile 60 — Mid Riffe Lake
            CLLocationCoordinate2D(latitude: 46.5350, longitude: -122.2900),
            // Mile 65 — Upper Riffe Lake
            CLLocationCoordinate2D(latitude: 46.5300, longitude: -122.2000),
            // Mile 70 — Above Riffe Lake, approaching Randle
            CLLocationCoordinate2D(latitude: 46.5280, longitude: -122.0800),
            // Mile 75 — Near Randle (V — USGS 14231000)
            CLLocationCoordinate2D(latitude: 46.5319, longitude: -121.9569),
            // Mile 80 — East of Randle
            CLLocationCoordinate2D(latitude: 46.5400, longitude: -121.8500),
            // Mile 85 — Between Randle and Packwood
            CLLocationCoordinate2D(latitude: 46.5600, longitude: -121.7500),
            // Mile 90 — Near Packwood (V — town GPS)
            CLLocationCoordinate2D(latitude: 46.6050, longitude: -121.6700),
            // Mile 95 — Above Packwood, approaching La Wis Wis
            CLLocationCoordinate2D(latitude: 46.6300, longitude: -121.5800),
            // Mile 100 — Near La Wis Wis, Ohanapecosh area
            CLLocationCoordinate2D(latitude: 46.6600, longitude: -121.5000),
            // Mile 105 — Headwaters, Mount Rainier glacial streams (V — GNIS)
            CLLocationCoordinate2D(latitude: 46.7300, longitude: -121.4500),
        ],

        "Bogachiel River": [
            // Mile 0 — Mouth at Sol Duc confluence, forming Quillayute River (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.9050, longitude: -124.5600),
            // Mile 5 — Lower Bogachiel, near USGS 12043015 (V)
            CLLocationCoordinate2D(latitude: 47.9029, longitude: -124.5455),
            // Mile 10 — Near Highway 101 crossing, south of Forks
            CLLocationCoordinate2D(latitude: 47.9100, longitude: -124.3800),
            // Mile 15 — Bogachiel State Park area
            CLLocationCoordinate2D(latitude: 47.9000, longitude: -124.2900),
            // Mile 20 — Approaching Olympic National Park boundary
            CLLocationCoordinate2D(latitude: 47.8900, longitude: -124.2000),
            // Mile 25 — Inside Olympic National Park, rainforest
            CLLocationCoordinate2D(latitude: 47.8800, longitude: -124.1100),
            // Mile 30 — Upper Bogachiel valley
            CLLocationCoordinate2D(latitude: 47.8600, longitude: -124.0200),
            // Mile 35 — Near Bogachiel Peak, headwaters area (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.8400, longitude: -123.9500),
        ],

        "Sol Duc River": [
            // Mile 0 — Mouth at Bogachiel confluence, forming Quillayute River (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.9050, longitude: -124.5600),
            // Mile 5 — Lower Sol Duc valley
            CLLocationCoordinate2D(latitude: 47.9200, longitude: -124.5000),
            // Mile 10 — Approaching Forks
            CLLocationCoordinate2D(latitude: 47.9400, longitude: -124.4300),
            // Mile 15 — Near Forks, USGS 12042400 at Hwy 101 (V)
            CLLocationCoordinate2D(latitude: 47.9500, longitude: -124.3800),
            // Mile 20 — East of Forks
            CLLocationCoordinate2D(latitude: 47.9550, longitude: -124.3000),
            // Mile 25 — Sol Duc valley
            CLLocationCoordinate2D(latitude: 47.9600, longitude: -124.2200),
            // Mile 30 — Mid-valley
            CLLocationCoordinate2D(latitude: 47.9650, longitude: -124.1400),
            // Mile 35 — Upper valley
            CLLocationCoordinate2D(latitude: 47.9700, longitude: -124.0600),
            // Mile 40 — Near Klahowya Campground area
            CLLocationCoordinate2D(latitude: 47.9700, longitude: -123.9800),
            // Mile 45 — Approaching Olympic National Park
            CLLocationCoordinate2D(latitude: 47.9700, longitude: -123.9000),
            // Mile 50 — Sol Duc Hot Springs area (V — NPS)
            CLLocationCoordinate2D(latitude: 47.9693, longitude: -123.8620),
            // Mile 55 — Above Sol Duc Falls, upper valley
            CLLocationCoordinate2D(latitude: 47.9500, longitude: -123.8000),
            // Mile 60 — Headwaters, Sol Duc Park area (V — GNIS)
            CLLocationCoordinate2D(latitude: 47.9400, longitude: -123.7500),
        ],
    ]

    /// Default search radius (km) from any spine point to count as "on" a river.
    static let defaultMaxDistanceKm: Double = 10.0
}
