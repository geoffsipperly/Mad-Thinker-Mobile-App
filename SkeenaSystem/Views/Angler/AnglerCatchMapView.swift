// Bend Fly Shop
// AnglerCatchMapView.swift — Mapbox Outdoors map plotting angler catch locations

import MapboxMaps
import SwiftUI

// MARK: - Annotation model

struct AnglerCatchAnnotation: Identifiable {
  let id: String
  let coordinate: CLLocationCoordinate2D
  let river: String
  let photoURL: URL?
  let createdAt: Date
}

// MARK: - SwiftUI view

struct AnglerCatchMapView: View {
  let reports: [CatchReportDTO]

  @State private var selectedAnnotation: AnglerCatchAnnotation?

  private var annotations: [AnglerCatchAnnotation] {
    reports.compactMap { r in
      guard let lat = r.latitude, let lon = r.longitude,
            lat.isFinite, lon.isFinite,
            abs(lat) <= 90, abs(lon) <= 180,
            !(lat == 0 && lon == 0) else { return nil }

      let date = Self.parseISO(r.createdAt) ?? Date()
      return AnglerCatchAnnotation(
        id: r.catch_id,
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        river: r.river,
        photoURL: r.photoURL,
        createdAt: date
      )
    }
  }

  private var initialViewport: Viewport {
    if let latest = annotations.sorted(by: { $0.createdAt > $1.createdAt }).first {
      return .camera(center: latest.coordinate, zoom: 10, bearing: 0, pitch: 0)
    }
    // Fallback: default map center from xcconfig
    let env = AppEnvironment.shared
    return .camera(
      center: CLLocationCoordinate2D(latitude: env.defaultMapLatitude, longitude: env.defaultMapLongitude),
      zoom: 8, bearing: 0, pitch: 0
    )
  }

  var body: some View {
    DarkPageTemplate {
      if annotations.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "map")
            .font(.system(size: 48))
            .foregroundColor(.gray)
          Text("No catch locations available")
            .font(.headline)
            .foregroundColor(.gray)
          Text("Catches with GPS coordinates will appear here.")
            .font(.subheadline)
            .foregroundColor(.gray.opacity(0.7))
        }
      } else {
        mapContent
          .ignoresSafeArea(edges: .bottom)
      }
    }
    .navigationTitle("Catch Map")
  }

  // MARK: - Map content

  @ViewBuilder
  private var mapContent: some View {
    Map(initialViewport: initialViewport) {
      // Catch pin annotations
      PointAnnotationGroup(annotations) { annotation in
        PointAnnotation(coordinate: annotation.coordinate)
          .image(.init(image: MapPinImage.pin(), name: "catch-pin"))
          .iconAnchor(IconAnchor.bottom)
          .onTapGesture { _ in
            selectedAnnotation = annotation
            return true
          }
      }

      // Callout for selected annotation
      if let selected = selectedAnnotation {
        MapViewAnnotation(coordinate: selected.coordinate) {
          AnglerCatchCalloutView(
            annotation: selected,
            onDismiss: { selectedAnnotation = nil }
          )
        }
        .allowOverlap(true)
        .variableAnchors([
          ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: 40),
        ])
      }
    }
    .mapStyle(.outdoors)
  }

  // MARK: - ISO date parser

  private static func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }
}
