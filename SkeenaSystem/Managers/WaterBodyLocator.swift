//
//  WaterBodyLocator.swift
//  SkeenaSystem
//
//  Polygon-based GPS lookup for water bodies (bays, sounds, canals).
//  Complements RiverLocator (which handles linear river spines).
//
//  Resolution priority in the app:
//  1. Check water body polygons (specific → general via checkOrder)
//  2. Check river spines (RiverLocator)
//  3. Fall back to defaultRiver / defaultWaterBody
//

import Foundation
import CoreLocation

/// A water body definition with its geofence polygon.
struct WaterBodyDefinition {
    let name: String
    let polygon: [CLLocationCoordinate2D]
}

/// Locates the user's position within known water body polygons.
///
/// The dataset is built dynamically from `WaterBodyAtlas.all`, filtered to only
/// include water bodies listed in `AppEnvironment.shared.lodgeWaterBodies`.
/// Check order follows `WaterBodyAtlas.checkOrder` (most specific first).
final class WaterBodyLocator {

    static let shared = WaterBodyLocator()

    /// Water bodies active for this app instance, ordered by specificity.
    private let waterBodies: [WaterBodyDefinition]

    private init() {
        let configured = Set(AppEnvironment.shared.lodgeWaterBodies)

        // Build list in check order (most specific first), filtered to configured bodies
        var bodies: [WaterBodyDefinition] = []

        for name in WaterBodyAtlas.checkOrder {
            guard configured.contains(name),
                  let polygon = WaterBodyAtlas.all[name],
                  polygon.count >= 3 else { continue }
            bodies.append(WaterBodyDefinition(name: name, polygon: polygon))
        }

        // Add any configured bodies not in checkOrder (append at end)
        for name in AppEnvironment.shared.lodgeWaterBodies {
            guard !bodies.contains(where: { $0.name == name }),
                  let polygon = WaterBodyAtlas.all[name],
                  polygon.count >= 3 else {
                if WaterBodyAtlas.all[name] == nil && configured.contains(name) {
                    AppLogging.log(
                        "[WaterBodyLocator] Warning: '\(name)' is in LODGE_WATER_BODIES but has no atlas entry",
                        level: .warn, category: .network
                    )
                }
                continue
            }
            bodies.append(WaterBodyDefinition(name: name, polygon: polygon))
        }

        waterBodies = bodies

        AppLogging.log(
            "[WaterBodyLocator] Loaded \(waterBodies.count) water body/bodies: \(waterBodies.map(\.name).joined(separator: ", "))",
            level: .info, category: .network
        )
    }

    // MARK: - Public API

    /// Returns true if any water bodies are configured.
    var hasWaterBodies: Bool { !waterBodies.isEmpty }

    /// Returns the name of the water body containing the given location, or nil.
    /// Checks more specific/smaller bodies first (per WaterBodyAtlas.checkOrder).
    func waterBodyName(at location: CLLocation?) -> String? {
        guard let location else { return nil }

        let point = location.coordinate
        for body in waterBodies {
            if Self.pointInPolygon(point: point, polygon: body.polygon) {
                return body.name
            }
        }
        return nil
    }

    // MARK: - Ray-casting point-in-polygon

    /// Standard ray-casting algorithm. Casts a horizontal ray east from the point
    /// and counts how many polygon edges it crosses. Odd = inside, even = outside.
    static func pointInPolygon(
        point: CLLocationCoordinate2D,
        polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]

            // Check if the ray crosses this edge
            if (pi.longitude > point.longitude) != (pj.longitude > point.longitude) {
                let intersectLat = pi.latitude
                    + (point.longitude - pi.longitude)
                    / (pj.longitude - pi.longitude)
                    * (pj.latitude - pi.latitude)

                if point.latitude < intersectLat {
                    inside.toggle()
                }
            }
            j = i
        }

        return inside
    }
}
