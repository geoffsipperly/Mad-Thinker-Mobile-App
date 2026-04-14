// Bend Fly Shop

import SwiftUI

// MARK: - ExploreView
//
// Explore screen for public-role users. Shows curated content sections:
//   - Citizen Scientists — horizontal carousel of placeholder video thumbnails
//   - Masterclasses — links to the community's Learn URL (opens in-app WebView)

struct ExploreView: View {
  @ObservedObject private var communityService = CommunityService.shared

  @State private var showMasterclass = false

  private var masterclassURL: URL? {
    let urlString = communityService.activeCommunityConfig.resolvedLearnUrl
    return URL(string: urlString)
  }

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "explore")
    }) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {

          // ── Citizen Scientists ─────────────────────────────────────
          VStack(alignment: .leading, spacing: 10) {
            Text("Citizen Scientists")
              .font(.subheadline.weight(.bold))
              .foregroundColor(.white)
              .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                videoThumbnailCard(image: "NetUse", title: "Proper Net Use")
                videoThumbnailCard(image: "FishHandling", title: "Fish Photo Handling")
                videoThumbnailCard(image: "CitizenScientists", title: "Taking Samples")
              }
              .padding(.horizontal, 16)
            }
          }

          // ── Masterclasses ─────────────────────────────────────────
          VStack(alignment: .leading, spacing: 10) {
            Text("Masterclasses")
              .font(.subheadline.weight(.bold))
              .foregroundColor(.white)
              .padding(.horizontal, 16)

            Button { showMasterclass = true } label: {
              ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                  Image("SteelheadPNW")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
                .frame(height: 180)
                  .overlay(
                    LinearGradient(
                      colors: [.clear, .black.opacity(0.7)],
                      startPoint: .top,
                      endPoint: .bottom
                    )
                  )

                HStack(alignment: .bottom) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Steelhead in the PNW")
                      .font(.subheadline.weight(.bold))
                      .foregroundColor(.white)
                    Text("Expert techniques and tactics")
                      .font(.caption)
                      .foregroundColor(.white.opacity(0.8))
                  }
                  Spacer()
                  Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.9))
                }
                .padding(12)
              }
              .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
          }

          Spacer(minLength: 16)
        }
        .padding(.top, 16)
      }
    }
    .navigationTitle("Learn")
    .navigationBarBackButtonHidden(true)
    .navigationDestination(isPresented: $showMasterclass) {
      if let url = masterclassURL {
        DarkPageTemplate {
          WebView(url: url)
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Masterclasses")
      }
    }
  }

  // MARK: - Video Thumbnail Card

  private func videoThumbnailCard(image: String, title: String) -> some View {
    Button { } label: {
      ZStack {
        Image(image)
          .resizable()
          .scaledToFill()
          .frame(width: 220, height: 180)
          .clipped()

        LinearGradient(
          colors: [.clear, .black.opacity(0.7)],
          startPoint: .top,
          endPoint: .bottom
        )

        VStack {
          Spacer()
          HStack(alignment: .bottom) {
            Text(title)
              .font(.subheadline.weight(.bold))
              .foregroundColor(.white)
            Spacer()
            Image(systemName: "play.circle.fill")
              .font(.title)
              .foregroundColor(.white.opacity(0.9))
          }
          .padding(12)
        }
      }
      .frame(width: 220, height: 180)
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }
}
