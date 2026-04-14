// Bend Fly Shop

import CoreLocation
import MapboxMaps
import SwiftUI

// MARK: - Annotation model

struct GuideLandingAnnotation: Identifiable {
  enum ReportType: String {
    case catch_ = "catch"
    case active = "active"
    case farmed = "farmed"
    case promising = "promising"
    case passed = "passed"

    var pinColor: UIColor {
      switch self {
      case .catch_:    return .systemBlue
      case .active:    return .systemGreen
      case .farmed:    return .systemOrange
      case .promising: return .systemYellow
      case .passed:    return .systemGray
      }
    }

    var pinName: String { "guide-pin-\(rawValue)" }
  }

  let id: String
  let coordinate: CLLocationCoordinate2D
  let reportType: ReportType
  let species: String?
  let lengthInches: Int?
  let date: Date
}

// MARK: - Map View

struct GuideLandingMapView: View {
  let reports: [MapReportDTO]
  /// Optional user GPS coordinate — used as a viewport fallback when no reports exist.
  var userLocation: CLLocationCoordinate2D? = nil

  @State private var selectedAnnotation: GuideLandingAnnotation? = nil

  // MARK: - Derived annotations

  private var annotations: [GuideLandingAnnotation] {
    reports.compactMap { r in
      guard let lat = r.latitude, let lon = r.longitude,
            lat.isFinite, lon.isFinite,
            abs(lat) <= 90, abs(lon) <= 180,
            !(lat == 0 && lon == 0) else { return nil }
      let type = GuideLandingAnnotation.ReportType(rawValue: r.type) ?? .passed
      return GuideLandingAnnotation(
        id: r.id,
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        reportType: type,
        species: r.species,
        lengthInches: r.lengthInches,
        date: Self.parseISO(r.date) ?? Date()
      )
    }
  }

  // MARK: - Group by type for PointAnnotationGroup (one group per pin style)

  private var catchAnnotations: [GuideLandingAnnotation]     { annotations.filter { $0.reportType == .catch_ } }
  private var activeAnnotations: [GuideLandingAnnotation]    { annotations.filter { $0.reportType == .active } }
  private var farmedAnnotations: [GuideLandingAnnotation]    { annotations.filter { $0.reportType == .farmed } }
  private var promisingAnnotations: [GuideLandingAnnotation] { annotations.filter { $0.reportType == .promising } }
  private var passedAnnotations: [GuideLandingAnnotation]    { annotations.filter { $0.reportType == .passed } }

  // MARK: - Initial viewport

  private var initialViewport: Viewport {
    // Center on most recent report
    if let latest = annotations.sorted(by: { $0.date > $1.date }).first {
      return .camera(center: latest.coordinate, zoom: 9, bearing: 0, pitch: 0)
    }
    // Fallback to user's current GPS location
    if let loc = userLocation {
      return .camera(center: loc, zoom: 9, bearing: 0, pitch: 0)
    }
    // Fallback to community geography
    let config = CommunityService.shared.activeCommunityConfig
    if let lat = config.resolvedDefaultMapLatitude,
       let lon = config.resolvedDefaultMapLongitude {
      return .camera(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        zoom: 8, bearing: 0, pitch: 0
      )
    }
    return .camera(
      center: CLLocationCoordinate2D(
        latitude: AppEnvironment.shared.defaultMapLatitude,
        longitude: AppEnvironment.shared.defaultMapLongitude
      ),
      zoom: 8, bearing: 0, pitch: 0
    )
  }

  // MARK: - Body

  var body: some View {
    Map(initialViewport: initialViewport) {
      annotationGroup(for: catchAnnotations,     type: .catch_)
      annotationGroup(for: activeAnnotations,    type: .active)
      annotationGroup(for: farmedAnnotations,    type: .farmed)
      annotationGroup(for: promisingAnnotations, type: .promising)
      annotationGroup(for: passedAnnotations,    type: .passed)

      // Callout for selected catch pin
      if let selected = selectedAnnotation, selected.reportType == .catch_ {
        MapViewAnnotation(coordinate: selected.coordinate) {
          GuideMapCalloutView(
            species: selected.species,
            lengthInches: selected.lengthInches,
            date: selected.date,
            onDismiss: { selectedAnnotation = nil }
          )
        }
        .allowOverlap(true)
        .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: 44)])
      }
    }
    .mapStyle(.satelliteStreets)
  }

  // MARK: - Helpers

  @MapContentBuilder
  private func annotationGroup(
    for group: [GuideLandingAnnotation],
    type: GuideLandingAnnotation.ReportType
  ) -> some MapContent {
    PointAnnotationGroup(group) { annotation in
      PointAnnotation(coordinate: annotation.coordinate)
        .image(.init(image: MapPinImage.pin(color: type.pinColor), name: type.pinName))
        .iconAnchor(.bottom)
        .onTapGesture { _ in
          if annotation.reportType == .catch_ {
            selectedAnnotation = annotation
          }
          return true
        }
    }
  }

  private static func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }
}

// MARK: - Legend

/// Compact colour legend shown below the map
struct GuideLandingMapLegend: View {
  private let items: [(String, UIColor)] = [
    ("Catch",     .systemBlue),
    ("Active",    .systemGreen),
    ("Farmed",    .systemOrange),
    ("Promising", .systemYellow),
    ("Passed",    .systemGray),
  ]

  var body: some View {
    HStack(spacing: 12) {
      ForEach(items, id: \.0) { label, uiColor in
        HStack(spacing: 4) {
          Circle()
            .fill(Color(uiColor))
            .frame(width: 8, height: 8)
          Text(label)
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.7))
        }
      }
    }
  }
}
