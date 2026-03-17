// Bend Fly Shop

import SwiftUI

/// A clean gray divider with a centered label.
struct SectionDivider: View {
  let label: String
  var body: some View {
    HStack(spacing: 8) {
      Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
      Text(label.uppercased())
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
      Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
    }
    .padding(.vertical, 6)
  }
}

/// Simple section header style for Form sections.
struct SectionHeader: View {
  let title: String
  var body: some View {
    Text(title)
      .font(.headline)
      .foregroundColor(.primary)
  }
}
