import UIKit
import CoreLocation

/// A photo plus any EXIF-derived metadata we care about.
struct PickedPhoto {
  let image: UIImage
  let exifDate: Date?
  let exifLocation: CLLocation?
}
