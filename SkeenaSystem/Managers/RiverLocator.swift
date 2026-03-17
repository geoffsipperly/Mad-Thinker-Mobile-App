//
//  RiverLocator.swift
//  River / Bend Fly Shop
//
//  Uses coordinate arrays defined in RiverCoordinates.swift
//  (e.g. nehalemCoordinates, wilsonCoordinates, etc.)
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
final class RiverLocator {

  static let shared = RiverLocator()

  // MARK: - Dataset

  /// Oregon Coast / Tillamook rivers.
  /// Coordinate arrays are defined in RiverCoordinates.swift.
  /// Replace placeholder coordinates with real KML spine data for accuracy.
  private let rivers: [RiverDefinition] = [
    // Bend Fly Shop – Oregon Coast

    RiverDefinition(
      name: "Nehalem River",
      communityID: AppEnvironment.shared.communityName,
      coordinates: nehalemCoordinates,
      maxDistanceKm: 10
    ),

    RiverDefinition(
      name: "Wilson River",
      communityID: AppEnvironment.shared.communityName,
      coordinates: wilsonCoordinates,
      maxDistanceKm: 10
    ),

    RiverDefinition(
      name: "Trask River",
      communityID: AppEnvironment.shared.communityName,
      coordinates: traskCoordinates,
      maxDistanceKm: 10
    ),

    RiverDefinition(
      name: "Nestucca River",
      communityID: AppEnvironment.shared.communityName,
      coordinates: nestuccaCoordinates,
      maxDistanceKm: 10
    ),

    RiverDefinition(
      name: "Kilchis River",
      communityID: AppEnvironment.shared.communityName,
      coordinates: kilchisCoordinates,
      maxDistanceKm: 10
    )
  ]

  private init() {}

  // MARK: - Public API

  /// Returns true if we have at least one river for this community.
    func hasRivers(forCommunity communityID: String) -> Bool {
      let normalized = communityID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return rivers.contains { $0.communityID.lowercased() == normalized }
    }

  /// Returns the best-matching river name for this location & community.
  ///
  /// Semantics:
  /// - If `location` is nil → "" (no river)
  /// - If no rivers are defined for this community → "" (no river)
  /// - For each river in this community:
  ///   - Compute the minimum distance to ANY of that river's coordinates.
  ///   - If that minimum distance ≤ `maxDistanceKm`, the river is a candidate.
  /// - Return the name of the candidate river with the smallest distance.
  /// - If no river is within its `maxDistanceKm` → "" (no river)
  func riverName(near location: CLLocation?, forCommunity communityID: String) -> String {
    // If we don't have a valid location, we can't resolve a river.
    guard let location else {
      return ""
    }

    // Filter for this community.
      let normalized = communityID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let communityRivers = rivers.filter { $0.communityID.lowercased() == normalized }

    guard !communityRivers.isEmpty else {
      return ""
    }

    var bestRiver: RiverDefinition?
    var bestDistanceKm = Double.greatestFiniteMagnitude

    // For each river in this community...
    for river in communityRivers {
      guard !river.coordinates.isEmpty else { continue }

      // Find the closest of this river's points.
      var bestDistanceForRiver = Double.greatestFiniteMagnitude

      for coord in river.coordinates {
        let riverLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceKm = location.distance(from: riverLoc) / 1000.0

        if distanceKm < bestDistanceForRiver {
          bestDistanceForRiver = distanceKm
        }
      }

      // Enforce the per-river max distance.
      guard bestDistanceForRiver <= river.maxDistanceKm else {
        continue
      }

      // Keep track of the globally closest qualifying river.
      if bestDistanceForRiver < bestDistanceKm {
        bestDistanceKm = bestDistanceForRiver
        bestRiver = river
      }
    }

    // If nothing qualified within its own radius, return "" ("no river").
    return bestRiver?.shortName ?? ""
  }
}
