//
//  RiverLocator.swift
//  SkeenaSystem
//
//  Dynamically builds its river dataset from RiverAtlas, filtered by
//  the community's LODGE_RIVERS configuration. No hardcoded river lists.
//

import Foundation
import CoreLocation

/// Represents a fishable river entry in our offline dataset.
///
/// Note: `coordinates` is a "spine" of points along the river.
/// We'll treat the river's coverage as the union of circles
/// around each of these points, with radius `maxDistanceKm`.
struct RiverDefinition {
  let name: String
  let communityID: String
  let coordinates: [CLLocationCoordinate2D]
  let maxDistanceKm: Double      // max distance from ANY point to count as on this river

  /// The river's base name with water-body suffixes stripped
  /// (e.g. "Nehalem River" → "Nehalem", "Kilchis River" → "Kilchis").
  var shortName: String {
    let suffixes = [" Creek", " River", " Lake", " Stream"]
    for suffix in suffixes where name.hasSuffix(suffix) {
      return String(name.dropLast(suffix.count))
    }
    return name
  }
}

/// Main entry point for river lookup. Designed to be community- and dataset-agnostic.
///
/// The river dataset is built dynamically from `RiverAtlas.all`, filtered to only
/// include rivers listed in `AppEnvironment.shared.lodgeRivers`. This means:
/// - `RiverCoordinates.swift` is a cumulative atlas (add rivers, never remove)
/// - `LODGE_RIVERS` in xcconfig controls which rivers are active per community
/// - No code changes needed in this file when onboarding a new community
final class RiverLocator {

  static let shared = RiverLocator()

  // MARK: - Dataset (built from atlas + config)

  /// Rivers active for this app instance, derived from LODGE_RIVERS config + RiverAtlas.
  private let rivers: [RiverDefinition]

  private init() {
    let communityName = AppEnvironment.shared.communityName
    let configuredRivers = AppEnvironment.shared.lodgeRivers

    rivers = configuredRivers.compactMap { riverName in
      guard let coords = RiverAtlas.all[riverName], !coords.isEmpty else {
        // River is in config but not in the atlas — log and skip
        AppLogging.log(
          "[RiverLocator] Warning: '\(riverName)' is in LODGE_RIVERS but has no atlas entry in RiverCoordinates.swift",
          level: .warn, category: .network
        )
        return nil
      }
      return RiverDefinition(
        name: riverName,
        communityID: communityName,
        coordinates: coords,
        maxDistanceKm: RiverAtlas.defaultMaxDistanceKm
      )
    }

    AppLogging.log(
      "[RiverLocator] Loaded \(rivers.count) river(s) for '\(communityName)': \(rivers.map(\.name).joined(separator: ", "))",
      level: .info, category: .network
    )
  }

  // MARK: - Public API

  /// Returns the best-matching river name for this location across all loaded rivers.
  ///
  /// Semantics:
  /// - If `location` is nil → "" (no river)
  /// - For each loaded river:
  ///   - Compute the minimum distance to ANY of that river's coordinates.
  ///   - If that minimum distance ≤ `maxDistanceKm`, the river is a candidate.
  /// - Return the name of the candidate river with the smallest distance.
  /// - If no river is within its `maxDistanceKm` → "" (no river)
  func riverName(near location: CLLocation?) -> String {
    guard let location else { return "" }
    guard !rivers.isEmpty else { return "" }

    var bestRiver: RiverDefinition?
    var bestDistanceKm = Double.greatestFiniteMagnitude

    for river in rivers {
      guard !river.coordinates.isEmpty else { continue }

      var bestDistanceForRiver = Double.greatestFiniteMagnitude

      for coord in river.coordinates {
        let riverLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceKm = location.distance(from: riverLoc) / 1000.0

        if distanceKm < bestDistanceForRiver {
          bestDistanceForRiver = distanceKm
        }
      }

      guard bestDistanceForRiver <= river.maxDistanceKm else { continue }

      if bestDistanceForRiver < bestDistanceKm {
        bestDistanceKm = bestDistanceForRiver
        bestRiver = river
      }
    }

    return bestRiver?.shortName ?? ""
  }
}
