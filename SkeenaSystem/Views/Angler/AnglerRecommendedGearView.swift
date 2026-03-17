// Bend Fly Shop
// AnglerRecommendedGearView.swift
import SwiftUI

private struct GearItem: Identifiable {
  let id = UUID()
  let title: String
  let subtitle: String?
}

private struct GearSection: Identifiable {
  let id = UUID()
  let title: String
  let description: String?   // optional white paragraph under the header
  let items: [GearItem]
}

struct AnglerRecommendedGearView: View {
  // MARK: - Data
  private let sections: [GearSection] = [
    GearSection(
      title: "",
      description: "Please Note: The lodge carries spare rods, reels, flies and tippet for guests",
      items: []
    ),

    GearSection(
      title: "Spey Rods: Recommended to bring",
      description: "Oregon Coast rivers vary from tidal estuaries to forested mountain streams. Match your rod selection to the water you'll be fishing.",
      items: [
        GearItem(
          title: "Smaller Creeks",
          subtitle: "Best: 8-weight switch rod (11-12 ft) matched with a very short Skagit head (<20 ft) such as an OPST Commando. A 7-weight works but is slightly under-gunned for bigger fish and weighted flies."
        ),
        GearItem(
          title: "Larger Rivers",
          subtitle: "Best: 12'6\"-12'9\" spey rod (7-8 weight). 7 weight performs well; 8 weight is useful too. Avoid anything smaller than a 7 weight."
        )
      ]
    ),

    GearSection(
      title: "Sink Tips: recommended to bring",
      description: nil,
      items: [
        GearItem(title: "10 ft tips", subtitle: "T-8, T-11, T-14"),
        GearItem(title: "7.5 ft tip", subtitle: "T-17, T-14, T11"),
        GearItem(title: "5 ft tips", subtitle: "T-17, T-14, T-11"),
        GearItem(title: "2.5 ft tip", subtitle: "T-11")
      ]
    ),

    GearSection(
      title: "Flies: Guides carry flies for guests to use",
      description: "Pink flies are popular; black and kingfisher blue also work. Use smaller/less flash in low water, larger/more flash in high water. Expect to lose flies under branches — bring plenty.",
      items: [
        GearItem(title: "Reverse marabou spey (pink/white)", subtitle: nil),
        GearItem(title: "Reverse marabou spey (black/blue)", subtitle: nil),
        GearItem(title: "Reverse marabou spey (blue/white)", subtitle: nil),
        GearItem(title: "Various weighted Tube flies (pink)", subtitle: nil),
        GearItem(title: "Various weighted tube flies (black/Blue)", subtitle: nil),
        GearItem(title: "unweighted Hoh Bo Spey (pink and black)", subtitle: nil)
      ]
    ),

    GearSection(
      title: "Fly weight and hooks",
      description: nil,
      items: [
        GearItem(title: "90% weighted flies / 10% unweighted", subtitle: nil),
        GearItem(title: "Medium → extra large lead eyes on sparse flies.", subtitle: nil),
        GearItem(title: "tungsten cone heads on sparse flies", subtitle: nil),
        GearItem(title: "avoid overdressed patterns", subtitle: nil),
        GearItem(title: "1/0 - size 2 heavy gauge hooks", subtitle: nil)
      ]
    ),

    GearSection(
      title: "Leaders & Tippet: recommended to bring",
      description: nil,
      items: [
        GearItem(title: "Tippet", subtitle: "Spool: Maxima Ultra Green 20-lb")
      ]
    ),

    GearSection(
      title: "Waders & Wading Gear: mandatory to bring",
      description: nil,
      items: [
        GearItem(title: "Waders", subtitle: "durable, breathable chest waders that will not easily tear"),
        GearItem(title: "Boots", subtitle: "Sturdy wading boots with rubber soles for hiking (not felt)"),
        GearItem(title: "Cleats", subtitle: "some guests highly recommend cleats"),
        GearItem(title: "Wading Jacket", subtitle: "Waterproof/breathable jacket for layering and rain protection.")
      ]
    )
  ]

  @State private var showOptional: Bool = false

  // MARK: - Body
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 12) {
        // Header
        VStack(spacing: 6) {
          HStack(alignment: .center, spacing: 12) {
            Image(AppEnvironment.shared.appLogoAsset)
              .resizable()
              .scaledToFit()
              .frame(width: 64, height: 64)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .shadow(radius: 4)
            VStack(alignment: .leading, spacing: 2) {
              Text("Recommended Gear")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
              Text(AppEnvironment.shared.forecastLocation)
                .font(.subheadline)
                .foregroundColor(.gray)
            }
            Spacer()
          }
          .padding(.horizontal, 16)
        }
        .padding(.top, 12)

        Divider().background(Color.white.opacity(0.08))

        // Content
        ScrollView {
          LazyVStack(spacing: 18, pinnedViews: []) {
            ForEach(sections) { section in
              VStack(alignment: .leading, spacing: 10) {
                if section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let desc = section.description {
                  Text(desc)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                } else {
                  Text(section.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color.blue)
                    .padding(.horizontal, 16)

                  if let desc = section.description {
                    Text(desc)
                      .foregroundColor(.white)
                      .font(.body)
                      .padding(.horizontal, 16)
                  }
                }

                VStack(spacing: 12) {
                  ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                      // bullet
                      Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                      VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                          .foregroundColor(.white)
                          .font(.body) // slightly smaller than the section header
                        if let subtitle = item.subtitle {
                          Text(subtitle)
                            .foregroundColor(.gray)
                            .font(.caption)
                        }
                      }
                      Spacer()
                    }
                    .padding(.horizontal, 16)
                  }
                }
              }
            }

            // Collapsible Optional Gear Section
            VStack(alignment: .leading, spacing: 10) {
              Button(action: { withAnimation { showOptional.toggle() } }) {
                HStack {
                  Text("See optional gear")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color.blue)
                  Spacer()
                  Image(systemName: showOptional ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
              }

              if showOptional {
                VStack(alignment: .leading, spacing: 10) {
                  Text("While the lodge carries spare rods, reels, flies and tippet for guests, some guest prefer to bring there own")
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.horizontal, 16)

                  // Render optional content by reusing existing sections if present.
                  // If you have a specific optional section in `sections`, you can filter and render it here. For now, we will display a helpful note.
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
              }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 32)
          }
          .padding(.vertical, 12)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .preferredColorScheme(.dark)
  }
}

struct AnglerRecommendedGearView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationView {
      AnglerRecommendedGearView()
    }
    .previewDevice("iPhone 12")
  }
}
