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
        guard let location else {
            AppLogging.log("[WaterBodyLocator] location is nil, returning nil", level: .debug, category: .ml)
            return nil
        }

        let point = location.coordinate
        AppLogging.log("[WaterBodyLocator] Checking point (\(point.latitude), \(point.longitude)) against \(waterBodies.count) water bodies", level: .debug, category: .ml)
        for body in waterBodies {
            let result = Self.pointInPolygon(point: point, polygon: body.polygon)
            AppLogging.log("[WaterBodyLocator] '\(body.name)' polygon (\(body.polygon.count) vertices): pointInPolygon = \(result)", level: .debug, category: .ml)
            if result {
                return body.name
            }
        }
        AppLogging.log("[WaterBodyLocator] No water body matched", level: .debug, category: .ml)
        return nil
    }

    // MARK: - Ray-casting point-in-polygon

    /// Epsilon for boundary tolerance (~11 metres of latitude/longitude).
    private static let epsilon: Double = 0.0001

    /// Ray-casting with boundary tolerance. Points exactly on a vertex or edge
    /// can produce incorrect results with pure ray-casting, so we also check
    /// proximity to every edge of the polygon.
    static func pointInPolygon(
        point: CLLocationCoordinate2D,
        polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }

        // 1. Standard ray-casting
        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]

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

        if inside { return true }

        // 2. Boundary tolerance — treat points within epsilon of any edge as inside
        j = polygon.count - 1
        for i in 0..<polygon.count {
            if distanceToSegment(point: point, a: polygon[j], b: polygon[i]) < epsilon {
                return true
            }
            j = i
        }

        return false
    }

    /// Minimum distance from a point to a line segment (in coordinate space).
    private static func distanceToSegment(
        point: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double {
        let dx = b.longitude - a.longitude
        let dy = b.latitude - a.latitude
        let lengthSq = dx * dx + dy * dy

        // Degenerate segment (a == b): just return distance to the vertex
        if lengthSq < 1e-15 {
            let px = point.longitude - a.longitude
            let py = point.latitude - a.latitude
            return (px * px + py * py).squareRoot()
        }

        // Project point onto the line, clamped to [0,1]
        let t = max(0, min(1,
            ((point.longitude - a.longitude) * dx + (point.latitude - a.latitude) * dy) / lengthSq
        ))

        let projLon = a.longitude + t * dx
        let projLat = a.latitude + t * dy

        let ex = point.longitude - projLon
        let ey = point.latitude - projLat
        return (ex * ex + ey * ey).squareRoot()
    }
}
