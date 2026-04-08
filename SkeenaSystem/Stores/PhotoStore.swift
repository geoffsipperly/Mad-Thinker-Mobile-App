// Bend Fly Shop

import UIKit

final class PhotoStore {
  static let shared = PhotoStore()
  private init() { createDirectoryIfNeeded() }

  // Keep all images in Documents/CatchPhotos
  private let folderName = "CatchPhotos"

  // MARK: - Public API

  /// Saves a UIImage as JPEG to Documents/CatchPhotos using the configured compression quality.
  /// - Returns: A stable filename you can store in Core Data (not a full path).
  @discardableResult
  func save(image: UIImage, preferredName: String? = nil, quality: CGFloat = AppEnvironment.shared.imageCompressionQuality) throws -> String {
    guard let data = image.jpegData(compressionQuality: quality) else {
      throw NSError(domain: "PhotoStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
    }
    let name: String = if let preferred = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !preferred.isEmpty {
      preferred.hasSuffix(".jpg") || preferred.hasSuffix(".jpeg") ? preferred : preferred + ".jpg"
    } else {
      UUID().uuidString + ".jpg"
    }

    let url = folderURL().appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    return name
  }

  /// Loads a UIImage given either a filename (recommended) or a full path string.
  func load(path pathOrFilename: String) -> UIImage? {
    let s = pathOrFilename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }

    let fileURL: URL = if s.contains("/Documents/") || s.hasPrefix("file://") {
      // Looks like a full path — use as-is.
      URL(fileURLWithPath: s.replacingOccurrences(of: "file://", with: ""))
    } else {
      // Treat as a filename inside our folder
      folderURL().appendingPathComponent(s)
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return UIImage(contentsOfFile: fileURL.path)
  }

  /// Returns a file URL for a stored filename (helpful for sharing/export).
  func url(for filename: String) -> URL {
    folderURL().appendingPathComponent(filename)
  }

  // MARK: - Helpers

  private func folderURL() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent(folderName, isDirectory: true)
  }

  private func createDirectoryIfNeeded() {
    let url = folderURL()
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return }
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
  }
}
