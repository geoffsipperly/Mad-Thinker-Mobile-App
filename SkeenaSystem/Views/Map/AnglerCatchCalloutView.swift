// Bend Fly Shop

import SwiftUI

/// SwiftUI callout displayed via MapViewAnnotation when a catch pin is tapped.
/// Shows the catch photo thumbnail, river name, and date — matching the previous
/// MapKit callout content.
struct AnglerCatchCalloutView: View {
  let annotation: AnglerCatchAnnotation
  let onDismiss: () -> Void

  private static let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
  }()

  var body: some View {
    HStack(spacing: 10) {
      // Photo thumbnail (48×48, matching previous MapKit callout)
      AsyncImage(url: annotation.photoURL) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .failure:
          Image(systemName: "photo")
            .font(.title3)
            .foregroundColor(.gray)
        default:
          ProgressView()
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))

      VStack(alignment: .leading, spacing: 2) {
        if !annotation.river.isEmpty {
          Text(annotation.river)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
        }
        Text(Self.dateFormatter.string(from: annotation.createdAt))
          .font(.caption)
          .foregroundColor(.secondary)
      }
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
