// Bend Fly Shop
// ForumImageCache.swift
// Memory + disk cache for forum media images

import UIKit

final class ForumImageCache {
  static let shared = ForumImageCache()

  // MARK: - Memory Cache

  private let memoryCache = NSCache<NSString, UIImage>()
  private let memoryCacheLimit: Int = 50 * 1024 * 1024 // 50MB

  // MARK: - Disk Cache

  private let fileManager = FileManager.default
  private let diskCacheLimit: Int = 200 * 1024 * 1024 // 200MB
  private let cacheDirectory: URL

  // MARK: - Concurrency

  private let queue = DispatchQueue(label: "com.epicwaters.forumImageCache", qos: .userInitiated)
  private let inFlightTracker = InFlightRequestTracker()

  // MARK: - Init

  private init() {
    // Set up memory cache limits
    memoryCache.totalCostLimit = memoryCacheLimit

    // Set up disk cache directory
    let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    cacheDirectory = cachesDir.appendingPathComponent("ForumMedia", isDirectory: true)

    // Create directory if needed
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    AppLogging.log("[ForumImageCache] Initialized at \(cacheDirectory.path)", level: .debug, category: .forum)
  }

  // MARK: - Public API

  /// Synchronous memory cache check
  func image(for url: URL) -> UIImage? {
    let key = cacheKey(for: url)
    return memoryCache.object(forKey: key as NSString)
  }

  /// Async load with memory -> disk -> network fallback
  func loadImage(from url: URL) async -> UIImage? {
    let key = cacheKey(for: url)

    // 1. Check memory cache
    if let cached = memoryCache.object(forKey: key as NSString) {
      return cached
    }

    // 2. Check if request is already in flight
    if let existingTask = await inFlightTracker.getTask(for: key) {
      return await existingTask.value
    }

    // 3. Create new task for this request
    let task = Task<UIImage?, Never> {
      // Check disk cache
      if let diskImage = loadFromDisk(key: key) {
        // Promote to memory cache
        let cost = diskImage.jpegData(compressionQuality: 1.0)?.count ?? 0
        memoryCache.setObject(diskImage, forKey: key as NSString, cost: cost)
        return diskImage
      }

      // Fetch from network
      guard let image = await fetchFromNetwork(url: url) else {
        return nil
      }

      // Save to caches
      let cost = image.jpegData(compressionQuality: 1.0)?.count ?? 0
      memoryCache.setObject(image, forKey: key as NSString, cost: cost)
      saveToDisk(image: image, key: key)

      return image
    }

    await inFlightTracker.setTask(task, for: key)

    let result = await task.value

    // Clean up in-flight tracking
    await inFlightTracker.removeTask(for: key)

    return result
  }

  /// Prefetch images in background
  func prefetch(urls: [URL]) {
    for url in urls {
      Task.detached(priority: .utility) { [weak self] in
        _ = await self?.loadImage(from: url)
      }
    }
  }

  /// Clear all caches
  func clearAll() {
    memoryCache.removeAllObjects()
    try? fileManager.removeItem(at: cacheDirectory)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    AppLogging.log("[ForumImageCache] Cleared all caches", level: .info, category: .forum)
  }

  // MARK: - Private

  private func cacheKey(for url: URL) -> String {
    // Use SHA256-like hash of URL for filename safety
    let urlString = url.absoluteString
    var hash: UInt64 = 5381
    for char in urlString.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(char)
    }
    return String(format: "%016llx", hash)
  }

  private func diskPath(for key: String) -> URL {
    cacheDirectory.appendingPathComponent(key)
  }

  private func loadFromDisk(key: String) -> UIImage? {
    let path = diskPath(for: key)
    guard fileManager.fileExists(atPath: path.path),
          let data = try? Data(contentsOf: path),
          let image = UIImage(data: data)
    else {
      return nil
    }
    return image
  }

  private func saveToDisk(image: UIImage, key: String) {
    queue.async { [weak self] in
      guard let self = self else { return }
      let path = self.diskPath(for: key)
      if let data = image.jpegData(compressionQuality: AppEnvironment.shared.imageCompressionQuality) {
        try? data.write(to: path, options: .atomic)
        self.trimDiskCacheIfNeeded()
      }
    }
  }

  private func trimDiskCacheIfNeeded() {
    // Simple LRU: delete oldest files if over limit
    guard let files = try? fileManager.contentsOfDirectory(
      at: cacheDirectory,
      includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
      options: .skipsHiddenFiles
    ) else { return }

    var totalSize: Int = 0
    var fileInfos: [(url: URL, date: Date, size: Int)] = []

    for file in files {
      guard let attrs = try? file.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey]),
            let date = attrs.contentAccessDate,
            let size = attrs.fileSize
      else { continue }
      totalSize += size
      fileInfos.append((file, date, size))
    }

    guard totalSize > diskCacheLimit else { return }

    // Sort by access date, oldest first
    fileInfos.sort { $0.date < $1.date }

    // Delete until under limit
    var currentSize = totalSize
    for info in fileInfos {
      guard currentSize > diskCacheLimit else { break }
      try? fileManager.removeItem(at: info.url)
      currentSize -= info.size
    }

    AppLogging.log("[ForumImageCache] Trimmed disk cache from \(totalSize) to \(currentSize) bytes", level: .debug, category: .forum)
  }

  private func fetchFromNetwork(url: URL) async -> UIImage? {
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let image = UIImage(data: data)
      else {
        return nil
      }
      return image
    } catch {
      AppLogging.log("[ForumImageCache] Network fetch failed: \(error.localizedDescription)", level: .warn, category: .forum)
      return nil
    }
  }
}

// MARK: - Async-safe in-flight request tracker

private actor InFlightRequestTracker {
  private var requests: [String: Task<UIImage?, Never>] = [:]

  func getTask(for key: String) -> Task<UIImage?, Never>? {
    requests[key]
  }

  func setTask(_ task: Task<UIImage?, Never>, for key: String) {
    requests[key] = task
  }

  func removeTask(for key: String) {
    requests.removeValue(forKey: key)
  }
}
