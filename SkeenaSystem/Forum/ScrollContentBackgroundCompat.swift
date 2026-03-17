// Bend Fly Shop

import SwiftUI

extension View {
  /// Hides the List/ScrollView background on iOS 16+; no-op on earlier iOS.
  @ViewBuilder
  func scrollContentBackgroundHiddenCompat() -> some View {
    if #available(iOS 16.0, *) {
      self.scrollContentBackground(.hidden)
    } else {
      self
    }
  }
}
