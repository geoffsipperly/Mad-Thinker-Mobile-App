// Bend Fly Shop

import UIKit

/// Generates a programmatic teardrop map pin image for use with Mapbox PointAnnotation.
/// Mapbox v11 requires an explicit image (no default marker like MapKit's MKMarkerAnnotationView).
enum MapPinImage {

  /// Returns a 30×40pt teardrop pin image filled with the given color.
  /// The image is registered once with Mapbox's annotation manager via the `name` parameter
  /// on `PointAnnotation.image(image:name:)`, so it is shared across all annotations via GPU texture.
  static func pin(color: UIColor = .systemBlue) -> UIImage {
    let size = CGSize(width: 30, height: 40)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      let path = UIBezierPath()
      let center = CGPoint(x: size.width / 2, y: 12)

      // Circle head
      path.addArc(
        withCenter: center, radius: 10,
        startAngle: .pi, endAngle: 0, clockwise: true
      )
      // Teardrop point
      path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
      path.addLine(to: CGPoint(x: size.width / 2 - 10, y: 12))
      path.close()

      color.setFill()
      path.fill()

      // White inner circle
      let dot = UIBezierPath(
        arcCenter: center, radius: 4,
        startAngle: 0, endAngle: .pi * 2, clockwise: true
      )
      UIColor.white.setFill()
      dot.fill()
    }
  }
}
