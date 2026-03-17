// Bend Fly Shop
// ForumMediaGrid.swift
// Display grid for forum post media with fullscreen viewing

import AVKit
import SwiftUI

/// Grid display for media attachments in a forum post
struct ForumMediaGrid: View {
  let media: [ForumMedia]

  @State private var selectedMedia: ForumMedia?

  // Layout: single image = full width, multiple = 2-column grid
  private var columns: [GridItem] {
    if media.count == 1 {
      return [GridItem(.flexible())]
    } else {
      return [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(media) { item in
        MediaThumbnailView(media: item)
          .frame(height: media.count == 1 ? 200 : 120)
          .clipped()
          .cornerRadius(8)
          .onTapGesture {
            selectedMedia = item
          }
      }
    }
    .fullScreenCover(item: $selectedMedia) { item in
      FullscreenMediaView(media: item)
    }
  }
}

// MARK: - Thumbnail View

struct MediaThumbnailView: View {
  let media: ForumMedia

  var body: some View {
    ZStack {
      if media.isImage {
        CachedAsyncImage(url: URL(string: media.publicUrl), contentMode: .fill)
      } else {
        // Video thumbnail with play button overlay
        VideoThumbnailFromURL(url: URL(string: media.publicUrl))
      }
    }
  }
}

// MARK: - Video Thumbnail (extracts first frame)

struct VideoThumbnailFromURL: View {
  let url: URL?

  @State private var thumbnail: UIImage?
  @State private var isLoading = true

  var body: some View {
    ZStack {
      if let thumbnail = thumbnail {
        Image(uiImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.black.opacity(0.3)
        if isLoading {
          ProgressView()
            .tint(.white)
        }
      }

      // Play button overlay
      Image(systemName: "play.circle.fill")
        .font(.system(size: 40))
        .foregroundColor(.white.opacity(0.9))
        .shadow(color: .black.opacity(0.5), radius: 4)
    }
    .onAppear {
      loadThumbnail()
    }
  }

  private func loadThumbnail() {
    guard let url = url else {
      isLoading = false
      return
    }

    // Check cache first
    if let cached = ForumImageCache.shared.image(for: url) {
      thumbnail = cached
      isLoading = false
      return
    }

    Task.detached(priority: .userInitiated) {
      let asset = AVAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 400, height: 400)

      do {
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        await MainActor.run {
          self.thumbnail = uiImage
          self.isLoading = false
        }
      } catch {
        await MainActor.run {
          AppLogging.log("[VideoThumbnail] Failed to generate thumbnail: \(error.localizedDescription)", level: .warn, category: .forum)
          self.isLoading = false
        }
      }
    }
  }
}

// MARK: - Fullscreen Media View

struct FullscreenMediaView: View {
  let media: ForumMedia
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if media.isImage {
        FullscreenImageView(url: URL(string: media.publicUrl))
      } else {
        FullscreenVideoView(url: URL(string: media.publicUrl))
      }

      // Close button
      VStack {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title)
              .foregroundColor(.white.opacity(0.8))
              .padding()
          }
        }
        Spacer()
      }
    }
    .statusBar(hidden: true)
  }
}

// MARK: - Fullscreen Image View

struct FullscreenImageView: View {
  let url: URL?

  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  var body: some View {
    GeometryReader { geo in
      CachedAsyncImage(url: url, contentMode: .fit) {
        ProgressView().tint(.white)
      }
      .scaleEffect(scale)
      .offset(offset)
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            let delta = value / lastScale
            lastScale = value
            scale = min(max(scale * delta, 1), 4)
          }
          .onEnded { _ in
            lastScale = 1.0
            if scale < 1.0 {
              withAnimation { scale = 1.0 }
            }
          }
      )
      .simultaneousGesture(
        DragGesture()
          .onChanged { value in
            offset = CGSize(
              width: lastOffset.width + value.translation.width,
              height: lastOffset.height + value.translation.height
            )
          }
          .onEnded { _ in
            lastOffset = offset
            if scale <= 1.0 {
              withAnimation {
                offset = .zero
                lastOffset = .zero
              }
            }
          }
      )
      .onTapGesture(count: 2) {
        withAnimation {
          if scale > 1 {
            scale = 1
            offset = .zero
            lastOffset = .zero
          } else {
            scale = 2
          }
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

// MARK: - Fullscreen Video View

struct FullscreenVideoView: View {
  let url: URL?

  @State private var player: AVPlayer?

  var body: some View {
    Group {
      if let player = player {
        VideoPlayer(player: player)
          .ignoresSafeArea()
      } else {
        ProgressView()
          .tint(.white)
      }
    }
    .onAppear {
      guard let url = url else { return }
      player = AVPlayer(url: url)
      player?.play()
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }
}

// MARK: - Preview Support

#if DEBUG
struct ForumMediaGrid_Previews: PreviewProvider {
  static var previews: some View {
    VStack {
      ForumMediaGrid(media: [
        ForumMedia(
          id: "1",
          file_name: "test.jpg",
          file_type: "image",
          mime_type: "image/jpeg",
          publicUrl: "https://picsum.photos/400/300"
        ),
        ForumMedia(
          id: "2",
          file_name: "test2.jpg",
          file_type: "image",
          mime_type: "image/jpeg",
          publicUrl: "https://picsum.photos/400/301"
        )
      ])
      .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
  }
}
#endif
