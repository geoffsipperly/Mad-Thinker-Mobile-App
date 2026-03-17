// Bend Fly Shop

import PhotosUI
import SwiftUI
import CoreLocation
import UIKit
import Photos

struct ImagePicker: UIViewControllerRepresentable {
  enum Source { case camera, library }
  let source: Source
  var onPickedPhoto: (PickedPhoto) -> Void

  func makeUIViewController(context: Context) -> UIViewController {
    switch source {
    case .camera:
      AppLogging.log("UIImagePickerController (camera) created", level: .debug, category: .angler)
      let vc = UIImagePickerController()
      vc.sourceType = .camera
      vc.delegate = context.coordinator
      return vc
    case .library:
      AppLogging.log("PHPickerViewController (library) created", level: .debug, category: .angler)
      var config = PHPickerConfiguration(photoLibrary: .shared())
      config.filter = .images
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = context.coordinator
      return picker
    }
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate,
    PHPickerViewControllerDelegate {
    let parent: ImagePicker
    init(_ parent: ImagePicker) { self.parent = parent }

      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        AppLogging.log("UIImagePicker didFinishPickingMediaWithInfo called", level: .debug, category: .angler)
        guard let image = info[.originalImage] as? UIImage else {
          AppLogging.log("UIImagePicker no original image in info; dismissing", level: .debug, category: .angler)
          picker.dismiss(animated: true)
          return
        }

        var exifDate: Date?
        var exifLocation: CLLocation?

        // If the picker gives us a PHAsset (e.g. when choosing from library), use its metadata
        if let asset = info[.phAsset] as? PHAsset {
          exifDate = asset.creationDate
          exifLocation = asset.location
        }

        let picked = PickedPhoto(
          image: image,
          exifDate: exifDate,
          exifLocation: exifLocation
        )
        AppLogging.log("UIImagePicker picked image: size=\(Int(image.size.width))x\(Int(image.size.height)), exifDate=\(exifDate != nil), exifLocation=\(exifLocation != nil)", level: .debug, category: .angler)
        parent.onPickedPhoto(picked)
        AppLogging.log("UIImagePicker calling onPickedPhoto and dismissing", level: .debug, category: .angler)
        picker.dismiss(animated: true)
      }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      AppLogging.log("UIImagePicker cancel tapped; dismissing", level: .debug, category: .angler)
      picker.dismiss(animated: true)
    }

      func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        AppLogging.log("PHPicker didFinishPicking called with results count=\(results.count)", level: .debug, category: .angler)
        guard let result = results.first else {
          AppLogging.log("PHPicker no results; dismissing", level: .debug, category: .angler)
          picker.dismiss(animated: true)
          return
        }

        let provider = result.itemProvider
        AppLogging.log("PHPicker provider registered types: \(provider.registeredTypeIdentifiers)", level: .debug, category: .angler)
        guard provider.canLoadObject(ofClass: UIImage.self) else {
          AppLogging.log("PHPicker provider cannot load UIImage; dismissing", level: .debug, category: .angler)
          picker.dismiss(animated: true)
          return
        }

        // Try to resolve the PHAsset so we can read EXIF date/location
        var asset: PHAsset?
        if let id = result.assetIdentifier {
          let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
          asset = fetchResult.firstObject
        }
        AppLogging.log("PHPicker resolved asset: \(asset != nil)", level: .debug, category: .angler)

        AppLogging.log("PHPicker starting loadObject UIImage", level: .debug, category: .angler)
        provider.loadObject(ofClass: UIImage.self) { object, _ in
          guard let img = object as? UIImage else {
            AppLogging.log("PHPicker loadObject returned non-UIImage; aborting", level: .debug, category: .angler)
            return
          }
          AppLogging.log("PHPicker loadObject succeeded: size=\(Int(img.size.width))x\(Int(img.size.height))", level: .debug, category: .angler)

          DispatchQueue.main.async {
            AppLogging.log("PHPicker delivering picked photo to parent", level: .debug, category: .angler)
            let picked = PickedPhoto(
              image: img,
              exifDate: asset?.creationDate,
              exifLocation: asset?.location
            )
            self.parent.onPickedPhoto(picked)
          }
        }

        AppLogging.log("PHPicker dismissing picker", level: .debug, category: .angler)
        picker.dismiss(animated: true)
      }

  }
}
