import XCTest
import UIKit
@testable import SkeenaSystem

/// Tests for the MapPinImage programmatic pin generator used with Mapbox annotations.
final class MapPinImageTests: XCTestCase {

  // MARK: - Basic Generation

  /// Default pin() returns a non-nil UIImage.
  func testPin_returnsNonNilImage() {
    let image = MapPinImage.pin()
    XCTAssertNotNil(image, "pin() should return a valid UIImage")
  }

  /// Pin image has expected 30×40 point dimensions.
  func testPin_hasExpectedDimensions() {
    let image = MapPinImage.pin()
    XCTAssertEqual(image.size.width, 30, accuracy: 0.01,
                   "Pin width should be 30pt")
    XCTAssertEqual(image.size.height, 40, accuracy: 0.01,
                   "Pin height should be 40pt")
  }

  /// Pin image has pixel data (non-empty rendering).
  func testPin_hasPixelData() {
    let image = MapPinImage.pin()
    guard let cgImage = image.cgImage else {
      XCTFail("Pin image should have a backing CGImage")
      return
    }
    XCTAssertGreaterThan(cgImage.width, 0, "CGImage width should be > 0")
    XCTAssertGreaterThan(cgImage.height, 0, "CGImage height should be > 0")
  }

  // MARK: - Custom Color

  /// Pin with a custom color returns a valid image.
  func testPin_customColor_returnsImage() {
    let image = MapPinImage.pin(color: .systemRed)
    XCTAssertNotNil(image, "pin(color:) should return a valid UIImage")
    XCTAssertEqual(image.size.width, 30, accuracy: 0.01)
    XCTAssertEqual(image.size.height, 40, accuracy: 0.01)
  }

  /// Pin with different colors produces images of the same dimensions.
  func testPin_differentColors_sameDimensions() {
    let bluePin = MapPinImage.pin(color: .systemBlue)
    let redPin = MapPinImage.pin(color: .systemRed)
    let greenPin = MapPinImage.pin(color: .systemGreen)

    XCTAssertEqual(bluePin.size, redPin.size,
                   "Blue and red pins should have the same size")
    XCTAssertEqual(redPin.size, greenPin.size,
                   "Red and green pins should have the same size")
  }

  // MARK: - PNG Encoding

  /// Pin image can be encoded to PNG data (validates rendering pipeline).
  func testPin_canEncodeToPNG() {
    let image = MapPinImage.pin()
    let pngData = image.pngData()
    XCTAssertNotNil(pngData, "Pin image should be encodable to PNG")
    XCTAssertGreaterThan(pngData?.count ?? 0, 0,
                         "PNG data should have non-zero byte count")
  }
}
