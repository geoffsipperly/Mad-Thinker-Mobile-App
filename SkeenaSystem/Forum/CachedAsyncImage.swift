// Bend Fly Shop
// CachedAsyncImage.swift
// SwiftUI view that loads images with ForumImageCache

import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
  let url: URL?
  let contentMode: ContentMode
  @ViewBuilder let placeholder: () -> Placeholder

  @State private var image: UIImage?
  @State private var isLoading = false

  init(
    url: URL?,
    contentMode: ContentMode = .fit,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.contentMode = contentMode
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else if isLoading {
        placeholder()
      } else {
        placeholder()
      }
    }
    .onAppear {
      loadImage()
    }
    .onChange(of: url) { _ in
      image = nil
      loadImage()
    }
  }

  private func loadImage() {
    guard let url = url else { return }

    // Check memory cache synchronously first
    if let cached = ForumImageCache.shared.image(for: url) {
      image = cached
      return
    }

    // Load asynchronously
    isLoading = true
    Task {
      let loadedImage = await ForumImageCache.shared.loadImage(from: url)
      await MainActor.run {
        self.image = loadedImage
        self.isLoading = false
      }
    }
  }
}

// MARK: - Convenience initializer with default placeholder

extension CachedAsyncImage where Placeholder == AnyView {
  init(url: URL?, contentMode: ContentMode = .fit) {
    self.url = url
    self.contentMode = contentMode
    self.placeholder = {
      AnyView(
        ZStack {
          Color.white.opacity(0.08)
          ProgressView()
            .tint(.white)
        }
      )
    }
  }
}
