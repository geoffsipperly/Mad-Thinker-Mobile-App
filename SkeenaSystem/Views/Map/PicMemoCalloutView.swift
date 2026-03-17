// Bend Fly Shop

import SwiftUI

/// SwiftUI callout displayed via MapViewAnnotation when a guide catch pin is tapped.
/// Shows species, lifecycle stage, length, angler number, and date — matching the
/// previous MapKit callout content from the TerrainMapView coordinator.
struct PicMemoCalloutView: View {
  let title: String
  let lifecycleStage: String?
  let lengthInches: Int
  let anglerNumber: String
  let createdAt: Date
  let onDismiss: () -> Void

  private static let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Species: \(title)")
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.primary)

      Text("Lifecycle: \(lifecycleStage ?? "—")")
        .font(.caption)
        .foregroundColor(.primary)

      Text("Length: \(lengthInches > 0 ? "\(lengthInches)\"" : "—")")
        .font(.caption)
        .foregroundColor(.primary)

      Text("Angler: \(anglerNumber)")
        .font(.caption)
        .foregroundColor(.primary)

      Text(Self.dateFormatter.string(from: createdAt))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(.regularMaterial)
        .shadow(radius: 4)
    )
    .onTapGesture { onDismiss() }
  }
}
