// Bend Fly Shop
// ForumMediaPicker.swift
// Multi-select photo/video picker for forum posts

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Represents a selected media item (image or video) ready for upload
struct SelectedMedia: Identifiable {
  let id = UUID()
  let image: UIImage?          // Thumbnail for display (nil for failed loads)
  let data: Data               // Full data for upload
  let fileName: String
  let mimeType: String
  let isVideo: Bool

  var sizeInMB: Double {
    Double(data.count) / (1024 * 1024)
  }
}

/// Multi-select media picker using PHPicker
struct ForumMediaPicker: UIViewControllerRepresentable {
  let maxSelections: Int
  let maxFileSizeMB: Double
  let onPicked: ([SelectedMedia]) -> Void
  let onError: (String) -> Void

  init(
    maxSelections: Int = 5,
    maxFileSizeMB: Double = 50,
    onPicked: @escaping ([SelectedMedia]) -> Void,
    onError: @escaping (String) -> Void = { _ in }
  ) {
    self.maxSelections = maxSelections
    self.maxFileSizeMB = maxFileSizeMB
    self.onPicked = onPicked
    self.onError = onError
  }

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.selectionLimit = maxSelections
    config.filter = .any(of: [.images, .videos])
    config.preferredAssetRepresentationMode = .current

    let picker = PHPickerViewController(configuration: config)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let parent: ForumMediaPicker

    init(parent: ForumMediaPicker) {
      self.parent = parent
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      picker.dismiss(animated: true)

      guard !results.isEmpty else {
        parent.onPicked([])
        return
      }

      Task {
        var media: [SelectedMedia] = []
        var errors: [String] = []

        for result in results {
          let itemProvider = result.itemProvider

          // Check for video first
          if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let videoMedia = await loadVideo(from: itemProvider) {
              if videoMedia.sizeInMB > parent.maxFileSizeMB {
                errors.append("\(videoMedia.fileName) exceeds \(Int(parent.maxFileSizeMB))MB limit")
              } else {
                media.append(videoMedia)
              }
            }
          }
          // Then check for image
          else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let imageMedia = await loadImage(from: itemProvider) {
              if imageMedia.sizeInMB > parent.maxFileSizeMB {
                errors.append("\(imageMedia.fileName) exceeds \(Int(parent.maxFileSizeMB))MB limit")
              } else {
                media.append(imageMedia)
              }
            }
          }
        }

        await MainActor.run {
          if !errors.isEmpty {
            parent.onError(errors.joined(separator: "\n"))
          }
          parent.onPicked(media)
        }
      }
    }

    private func loadImage(from provider: NSItemProvider) async -> SelectedMedia? {
      await withCheckedContinuation { continuation in
        provider.loadObject(ofClass: UIImage.self) { object, _ in
          guard let image = object as? UIImage else {
            continuation.resume(returning: nil)
            return
          }

          // Determine format - prefer JPEG for photos
          let fileName = "image_\(UUID().uuidString.prefix(8)).jpg"
          guard let data = image.jpegData(compressionQuality: AppEnvironment.shared.imageCompressionQuality) else {
            continuation.resume(returning: nil)
            return
          }

          let media = SelectedMedia(
            image: image,
            data: data,
            fileName: fileName,
            mimeType: "image/jpeg",
            isVideo: false
          )
          continuation.resume(returning: media)
        }
      }
    }

    private func loadVideo(from provider: NSItemProvider) async -> SelectedMedia? {
      await withCheckedContinuation { continuation in
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
          guard let url = url else {
            continuation.resume(returning: nil)
            return
          }

          // Copy to temp location (provider URL is temporary)
          let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

          do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            let data = try Data(contentsOf: tempURL)

            // Generate thumbnail
            let thumbnail = self.generateVideoThumbnail(url: tempURL)

            // Determine mime type
            let ext = url.pathExtension.lowercased()
            let mimeType = ext == "mov" ? "video/quicktime" : "video/mp4"
            let fileName = "video_\(UUID().uuidString.prefix(8)).\(ext.isEmpty ? "mp4" : ext)"

            let media = SelectedMedia(
              image: thumbnail,
              data: data,
              fileName: fileName,
              mimeType: mimeType,
              isVideo: true
            )

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            continuation.resume(returning: media)
          } catch {
            AppLogging.log("[ForumMediaPicker] Video load failed: \(error.localizedDescription)", level: .warn, category: .forum)
            continuation.resume(returning: nil)
          }
        }
      }
    }

    private func generateVideoThumbnail(url: URL) -> UIImage? {
      let asset = AVAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true

      do {
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: cgImage)
      } catch {
        return nil
      }
    }
  }
}

// MARK: - Preview Grid for Selected Media

struct SelectedMediaGrid: View {
  let media: [SelectedMedia]
  let onRemove: (SelectedMedia) -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8)
  ]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(media) { item in
        ZStack(alignment: .topTrailing) {
          // Thumbnail
          if let image = item.image {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(height: 80)
              .clipped()
              .cornerRadius(8)
          } else {
            Rectangle()
              .fill(Color.white.opacity(0.1))
              .frame(height: 80)
              .cornerRadius(8)
          }

          // Video indicator
          if item.isVideo {
            Image(systemName: "video.fill")
              .font(.caption)
              .foregroundColor(.white)
              .padding(4)
              .background(Color.black.opacity(0.6))
              .cornerRadius(4)
              .padding(4)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          }

          // Remove button
          Button {
            onRemove(item)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title3)
              .foregroundColor(.white)
              .background(Color.black.opacity(0.5).clipShape(Circle()))
          }
          .padding(4)
        }
      }
    }
  }
}

// MARK: - Add Media Button

struct AddMediaButton: View {
  let currentCount: Int
  let maxCount: Int
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.subheadline)
        Text(currentCount > 0 ? "\(currentCount)/\(maxCount)" : "Add Media")
          .font(.subheadline)
      }
      .foregroundColor(.white.opacity(0.8))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.12))
      .cornerRadius(8)
    }
    .disabled(currentCount >= maxCount)
    .opacity(currentCount >= maxCount ? 0.5 : 1)
  }
}
