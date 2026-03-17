import XCTest
@testable import SkeenaSystem

/// Tests for ForumImageCache hash function and basic cache operations.
///
/// Validates:
/// 1. `cacheKey` DJB2 hash is deterministic
/// 2. Different URLs produce different keys
/// 3. Cache singleton exists and doesn't crash
/// 4. `clearAll` doesn't crash
final class ForumImageCacheTests: XCTestCase {

  // MARK: - Properties

  private let cache = ForumImageCache.shared

  // MARK: - Helpers

  /// Replicates `ForumImageCache.cacheKey(for:)` for direct testing.
  /// Uses the same DJB2-style hash algorithm.
  private func cacheKey(for url: URL) -> String {
    let urlString = url.absoluteString
    var hash: UInt64 = 5381
    for char in urlString.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(char)
    }
    return String(format: "%016llx", hash)
  }

  // MARK: - cacheKey Determinism Tests

  func testCacheKey_deterministic_sameUrlSameKey() {
    let url = URL(string: "https://example.com/image.jpg")!
    let key1 = cacheKey(for: url)
    let key2 = cacheKey(for: url)
    XCTAssertEqual(key1, key2, "Same URL should always produce the same key")
  }

  func testCacheKey_differentUrls_differentKeys() {
    let url1 = URL(string: "https://example.com/image1.jpg")!
    let url2 = URL(string: "https://example.com/image2.jpg")!
    let key1 = cacheKey(for: url1)
    let key2 = cacheKey(for: url2)
    XCTAssertNotEqual(key1, key2, "Different URLs should produce different keys")
  }

  func testCacheKey_format_is16CharHex() {
    let url = URL(string: "https://example.com/test.png")!
    let key = cacheKey(for: url)
    XCTAssertEqual(key.count, 16, "Key should be 16 hex characters")

    let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
    for char in key.unicodeScalars {
      XCTAssertTrue(hexChars.contains(char), "Key should only contain hex characters, found: \(char)")
    }
  }

  func testCacheKey_longUrl_doesNotCrash() {
    let longPath = String(repeating: "a", count: 10000)
    let url = URL(string: "https://example.com/\(longPath)")!
    let key = cacheKey(for: url)
    XCTAssertEqual(key.count, 16, "Long URL should still produce 16-char key")
  }

  func testCacheKey_urlWithQueryParams_differentFromWithout() {
    let url1 = URL(string: "https://example.com/image.jpg")!
    let url2 = URL(string: "https://example.com/image.jpg?width=200")!
    let key1 = cacheKey(for: url1)
    let key2 = cacheKey(for: url2)
    XCTAssertNotEqual(key1, key2, "URL with query params should have different key")
  }

  // MARK: - Cache Singleton Tests

  func testSharedInstance_isSingleton() {
    let instance1 = ForumImageCache.shared
    let instance2 = ForumImageCache.shared
    XCTAssertTrue(instance1 === instance2, "shared should return the same instance")
  }

  // MARK: - Memory Cache Tests

  func testMemoryCache_returnsNilForUnknownUrl() {
    let url = URL(string: "https://example.com/unknown-\(UUID().uuidString).jpg")!
    let result = cache.image(for: url)
    XCTAssertNil(result, "Should return nil for URL not in cache")
  }

  // MARK: - clearAll Tests

  func testClearAll_doesNotCrash() {
    // Just verify it doesn't throw or crash
    cache.clearAll()
    // After clearing, nothing should be cached
    let url = URL(string: "https://example.com/after-clear.jpg")!
    XCTAssertNil(cache.image(for: url))
  }
}
