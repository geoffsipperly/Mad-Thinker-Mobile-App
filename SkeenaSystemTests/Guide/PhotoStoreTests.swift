import XCTest
import UIKit
@testable import SkeenaSystem

/// Tests for PhotoStore save/load round-trip, filename handling,
/// and path resolution.
///
/// Validates:
/// 1. Save returns a .jpg filename
/// 2. Preferred names are respected (with .jpg appended if needed)
/// 3. Load round-trips correctly
/// 4. Edge cases: empty path, missing files, full path resolution
final class PhotoStoreTests: XCTestCase {

  // MARK: - Properties

  private let store = PhotoStore.shared
  private var savedFilenames: [String] = []

  override func tearDown() {
    // Clean up any photos saved during tests
    for filename in savedFilenames {
      let url = store.url(for: filename)
      try? FileManager.default.removeItem(at: url)
    }
    savedFilenames.removeAll()
    super.tearDown()
  }

  // MARK: - Helpers

  /// Creates a small 1x1 red test image.
  private func makeTestImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
    return renderer.image { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    }
  }

  // MARK: - save Tests

  func testSave_returnsFilenameEndingInJpg() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image)
    savedFilenames.append(filename)

    XCTAssertTrue(filename.hasSuffix(".jpg"), "Filename should end in .jpg, got: \(filename)")
  }

  func testSave_withPreferredName_usesPreferredName() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "test-photo.jpg")
    savedFilenames.append(filename)

    XCTAssertEqual(filename, "test-photo.jpg")
  }

  func testSave_preferredNameWithoutJpg_addsJpgExtension() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "my-catch")
    savedFilenames.append(filename)

    XCTAssertEqual(filename, "my-catch.jpg")
  }

  func testSave_preferredNameWithJpeg_keptAsIs() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "my-catch.jpeg")
    savedFilenames.append(filename)

    XCTAssertEqual(filename, "my-catch.jpeg")
  }

  func testSave_emptyPreferredName_fallsBackToUUID() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "   ")
    savedFilenames.append(filename)

    XCTAssertTrue(filename.hasSuffix(".jpg"), "Should end in .jpg")
    // UUID filenames are 36 chars + ".jpg" = 40 chars
    XCTAssertTrue(filename.count > 10, "Should be a UUID-based filename, got: \(filename)")
  }

  func testSave_nilPreferredName_fallsBackToUUID() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: nil)
    savedFilenames.append(filename)

    XCTAssertTrue(filename.hasSuffix(".jpg"), "Should end in .jpg")
  }

  func testSave_fileExistsOnDisk() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "disk-check.jpg")
    savedFilenames.append(filename)

    let url = store.url(for: filename)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist on disk")
  }

  // MARK: - load Tests

  func testLoad_roundTrip_returnsNonNilImage() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "roundtrip.jpg")
    savedFilenames.append(filename)

    let loaded = store.load(path: filename)
    XCTAssertNotNil(loaded, "Should load previously saved image")
  }

  func testLoad_emptyPath_returnsNil() {
    let result = store.load(path: "")
    XCTAssertNil(result, "Empty path should return nil")
  }

  func testLoad_whitespaceOnlyPath_returnsNil() {
    let result = store.load(path: "   ")
    XCTAssertNil(result, "Whitespace-only path should return nil")
  }

  func testLoad_nonexistentFilename_returnsNil() {
    let result = store.load(path: "does-not-exist-\(UUID().uuidString).jpg")
    XCTAssertNil(result, "Nonexistent file should return nil")
  }

  func testLoad_fullPathWithDocuments_recognized() throws {
    let image = makeTestImage()
    let filename = try store.save(image: image, preferredName: "fullpath-test.jpg")
    savedFilenames.append(filename)

    let url = store.url(for: filename)
    let loaded = store.load(path: url.path)
    XCTAssertNotNil(loaded, "Should load from full path containing /Documents/")
  }

  // MARK: - url Tests

  func testUrl_containsCatchPhotosDirectory() {
    let url = store.url(for: "test.jpg")
    XCTAssertTrue(url.path.contains("CatchPhotos"), "URL should be under CatchPhotos directory")
  }

  func testUrl_endsWithFilename() {
    let url = store.url(for: "my-photo.jpg")
    XCTAssertEqual(url.lastPathComponent, "my-photo.jpg")
  }
}
