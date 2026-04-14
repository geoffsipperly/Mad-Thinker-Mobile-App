// Bend Fly Shop

import SwiftUI

struct TermsAndConditionsView: View {
  let title: String
  let bodyText: String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(bodyText)
            .font(.body)
            .foregroundColor(.white)
            .padding(.top, 8)

          // Optional spacer so the user can clearly scroll to "the bottom"
          Spacer(minLength: 40)
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
      }
      .background(Color.black.ignoresSafeArea())
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
              .font(.title3.weight(.semibold))
              .foregroundColor(.white)
          }
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}
