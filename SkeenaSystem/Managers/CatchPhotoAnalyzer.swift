// Bend Fly Shop

import CoreLocation
import CoreML
import UIKit
import Vision

struct CatchPhotoAnalysis {
  let riverName: String?
  let species: String?
  let sex: String?
  let estimatedLength: String?
  // New optional field with a default value so existing initializers still compile
  let lifecycleStage: String? = nil
}

final class CatchPhotoAnalyzer {
  // private let communityID: String
  private let riverLocator: RiverLocator

  // ViT species model (raw MLModel)
  private let coreMLModel: MLModel

  // YOLOv8 detector from best.mlpackage
  private let detectorModel: best

  // Species labels for ViT
    private let speciesLabels: [String] = [
      "articchar_holding",
      "articchar_traveler",
      "brook_holding",
      "grayling",
      "rainbow_holding",
      "rainbow_lake",
      "rainbow_traveler",
      "steelhead_holding",
      "steelhead_traveler"
    ]

  // MARK: - Init

  init(riverLocator: RiverLocator = .shared) {
    self.riverLocator = riverLocator

    let config = MLModelConfiguration()

    // Species model (ViTFishSpecies.mlpackage)
    guard let speciesURL = Bundle.main.url(forResource: "ViTFishSpecies", withExtension: "mlmodelc") else {
      fatalError("❌ Could not find ViTFishSpecies.mlmodelc in app bundle")
    }
    self.coreMLModel = try! MLModel(contentsOf: speciesURL, configuration: config)

    // YOLOv8 detector (best.mlpackage)
    self.detectorModel = try! best(configuration: config)
  }

  // MARK: - Main analysis entry point

  func analyze(
    image: UIImage,
    location: CLLocation?,
    communityID: String?
  ) async -> CatchPhotoAnalysis {
    // 1. River name / status via offline locator + community context
    var riverDisplay: String?

    if let communityID {
      if !riverLocator.hasRivers(forCommunity: communityID) {
        // Scenario 3: community has no rivers configured
        riverDisplay = "No rivers configured for \(communityID)"
      } else {
        // We *do* have rivers for this community → try to detect one
        let name = riverLocator.riverName(near: location, forCommunity: communityID)

        if name.isEmpty {
          // Scenario 2: community has rivers, but no match for this location
          riverDisplay = "No river detected for \(communityID)"
        } else {
          // Normal case: matched a specific river
          riverDisplay = name
        }
      }
    } else {
      // No community ID given; VM will fall back to its generic message
      riverDisplay = nil
    }

    // 2. Species via ViT
    let vitSpeciesGuess = runViT(on: image)

    let speciesText: String?
    if let idx = vitSpeciesGuess,
       idx >= 0,
       idx < speciesLabels.count {
      let rawLabel = speciesLabels[idx]
      let prettyLabel = rawLabel.replacingOccurrences(of: "_", with: " ")

      speciesText = "Species (model): \(prettyLabel)"
    } else {
      speciesText = "Model could not confidently classify this fish"
    }

    // 3. Sex via ViTFishSex (iOS 16+), fallback to Unknown on older OS
    let sexText: String? = if #available(iOS 16.0, *) {
      if let sexLabel = runSexClassifier(on: image) {
        "Sex (model): \(sexLabel)"
      } else {
        "Unknown"
      }
    } else {
      "Unknown"
    }

    // 4. Length via YOLOv8 detector
    //    Start with a fallback so we *always* see something in the UI.
    var lengthText: String? = "Length estimate not available (photo estimate failed)"

    if let box = runFishDetector(on: image) {
      let result = estimateLength(from: box, imageSize: image.size)
      lengthText = result.display
      AppLogging.log({ "Detector found box with conf \(box.confidence), estimated length: \(result.display)" }, level: .info, category: .ml)
    } else {
      AppLogging.log("Detector did not return any box above confidence/shape thresholds.", level: .warn, category: .ml)
    }

    return CatchPhotoAnalysis(
      riverName: riverDisplay,
      species: speciesText,
      sex: sexText,
      estimatedLength: lengthText
      // lifecycleStage will default to nil
    )
  }

  // MARK: - ViT inference (species)

  /// Runs the ViT species model on a UIImage and returns the index of the maximum logit, if available.
  private func runViT(on image: UIImage) -> Int? {
    guard let inputArray = try? makeInputArray(from: image) else {
      return nil
    }

    // Wrap the MLMultiArray in an MLFeatureProvider
    let provider = ViTInputFeatureProvider(imageArray: inputArray)

    guard let output = try? coreMLModel.prediction(from: provider) else {
      return nil
    }

    // Grab the first output feature that is a multiArray
    guard
      let outputName = output.featureNames.first,
      let logits = output.featureValue(for: outputName)?.multiArrayValue
    else {
      return nil
    }

    return argmax(logits)
  }

  /// Returns the index of the largest value in the MLMultiArray (assumed 1-D or flattenable).
  private func argmax(_ array: MLMultiArray) -> Int? {
    guard array.count > 0 else { return nil }  // swiftlint:disable:this empty_count

    var bestIndex = 0
    var bestValue = Float(array[0].floatValue)

    for i in 1 ..< array.count {
      let v = array[i].floatValue
      if v > bestValue {
        bestValue = v
        bestIndex = i
      }
    }
    return bestIndex
  }

  // MARK: - ViT sex classifier (iOS 16+)

  /// Runs the ViTFishSex model on a UIImage and returns "male" / "female" or nil.
  @available(iOS 16.0, *)
  private func runSexClassifier(on image: UIImage) -> String? {
    guard let inputArray = try? makeInputArray(from: image) else {
      AppLogging.log("runSexClassifier: failed to create input array", level: .error, category: .ml)
      return nil
    }

    // Create the sex model on demand. If you want, we can later cache it.
    let config = MLModelConfiguration()
    guard let model = try? ViTFishSex(configuration: config) else {
      AppLogging.log("runSexClassifier: failed to create ViTFishSex model", level: .error, category: .ml)
      return nil
    }

    // ViTFishSex was exported with a single Tensor input (ct.TensorType),
    // so the generated API should look like `prediction(input: MLMultiArray)`.
    guard let output = try? model.prediction(input: inputArray) else {
      AppLogging.log("runSexClassifier: model prediction failed", level: .error, category: .ml)
      return nil
    }

    let label = output.classLabel // "female" or "male"
    AppLogging.log({ "runSexClassifier: label=\(label)" }, level: .info, category: .ml)

    // Normalize to lowercase for consistency with CatchChatViewModel's text parsing
    return label.lowercased()
  }

  // MARK: - Image preprocessing for ViT / ViTFishSex

  /// Converts a UIImage into a 1×3×224×224 Float32 MLMultiArray in [0, 1].
  private func makeInputArray(from image: UIImage) throws -> MLMultiArray {
    let targetSize = CGSize(width: 224, height: 224)

    // 1) Resize the image to 224x224
    guard let resized = resize(image: image, to: targetSize),
          let cgImage = resized.cgImage
    else {
      throw PreprocessError.cannotResize
    }

    let width = Int(targetSize.width)
    let height = Int(targetSize.height)

    // 2) Draw into RGBA8 buffer
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8

    var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &rawData,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw PreprocessError.cannotCreateContext
    }

    context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

    // 3) Create MLMultiArray of shape [1, 3, 224, 224]
    let shape: [NSNumber] = [1, 3, NSNumber(value: height), NSNumber(value: width)]
    let array = try MLMultiArray(shape: shape, dataType: .float32)

    // Fill in channel-first order: [batch, channel, y, x]
    let channelStride = height * width

    for y in 0 ..< height {
      for x in 0 ..< width {
        let pixelIndex = y * bytesPerRow + x * bytesPerPixel
        let r = Float(rawData[pixelIndex + 0]) / 255.0
        let g = Float(rawData[pixelIndex + 1]) / 255.0
        let b = Float(rawData[pixelIndex + 2]) / 255.0

        let hwIndex = y * width + x

        let rIndex = 0 * channelStride + hwIndex
        let gIndex = 1 * channelStride + hwIndex
        let bIndex = 2 * channelStride + hwIndex

        array[rIndex] = NSNumber(value: r)
        array[gIndex] = NSNumber(value: g)
        array[bIndex] = NSNumber(value: b)
      }
    }

    return array
  }

  private func resize(image: UIImage, to targetSize: CGSize) -> UIImage? {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0 // we want logical pixels

    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let result = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return result
  }

  private enum PreprocessError: Error {
    case cannotResize
    case cannotCreateContext
  }

  // MARK: - Detector helpers (YOLOv8 → length)

  private struct NormalizedBox {
    let xCenter: CGFloat // pixels in 640×640 coordinate space
    let yCenter: CGFloat // pixels in 640×640 coordinate space
    let width: CGFloat   // pixels in 640×640 coordinate space
    let height: CGFloat  // pixels in 640×640 coordinate space
    let confidence: Float
  }
    
    /// Runs the YOLOv8 detector and returns the highest-confidence *fish* box, if any.
    /// Handles both [1, C, A] and [1, A, C] output layouts (C = 4 + numClasses, A = anchors).
    private func runFishDetector(on image: UIImage) -> NormalizedBox? {
      guard let cgImage = image.cgImage else {
        AppLogging.log("runFishDetector: could not get CGImage from UIImage", level: .error, category: .ml)
        return nil
      }

      // YOLOv8 CoreML export expects 640×640
      let inputSize = CGSize(width: 640, height: 640)

      guard let pixelBuffer = cgImage.toPixelBuffer(targetSize: inputSize) else {
        AppLogging.log("runFishDetector: failed to create pixel buffer", level: .error, category: .ml)
        return nil
      }

      guard let output = try? detectorModel.prediction(image: pixelBuffer) else {
        AppLogging.log("runFishDetector: model prediction failed", level: .error, category: .ml)
        return nil
      }

      let arr = output.var_913

      guard arr.shape.count == 3,
            arr.shape[0].intValue == 1 else {
        AppLogging.log({ "runFishDetector: unexpected output shape \(arr.shape)" }, level: .error, category: .ml)
        return nil
      }

      let dim1 = arr.shape[1].intValue
      let dim2 = arr.shape[2].intValue

      // Decide which axis is channels (small) vs anchors (large, ~8400)
      let channels: Int
      let numAnchors: Int
      let channelsOnSecondAxis: Bool

      if dim1 <= dim2 {
        // Layout: [1, C, A]
        channels = dim1
        numAnchors = dim2
        channelsOnSecondAxis = true
      } else {
        // Layout: [1, A, C]
        channels = dim2
        numAnchors = dim1
        channelsOnSecondAxis = false
      }

      guard channels > 4 else {
        AppLogging.log({ "runFishDetector: not enough channels (\(channels)) for xywh+classes" }, level: .error, category: .ml)
        return nil
      }

      let numClasses = channels - 4

      // Helper closure to read arr[0, channel, anchor] or arr[0, anchor, channel]
      let read: (_ channelIndex: Int, _ anchorIndex: Int) -> Double = { ch, an in
        let idx: [NSNumber]
        if channelsOnSecondAxis {
          // [1, C, A]
          idx = [0, NSNumber(value: ch), NSNumber(value: an)]
        } else {
          // [1, A, C]
          idx = [0, NSNumber(value: an), NSNumber(value: ch)]
        }
        return arr[idx].doubleValue
      }

      AppLogging.log({ "runFishDetector: output shape=\(arr.shape), channels=\(channels), anchors=\(numAnchors), channelsOnSecondAxis=\(channelsOnSecondAxis)" }, level: .debug, category: .ml)

      // Assumes data.yaml: names: ['fish', 'person'] → fish = class 0
      let fishClassIndex = 0

      // Threshold for our "good" candidate (geometry-filtered)
      let minPrimaryConfidence: Float = AppEnvironment.shared.fishDetectMinConfidence

      // Geometry thresholds
      let imgW: CGFloat = 640.0
      let imgH: CGFloat = 640.0
      let minAspect: CGFloat = 1.0        // width / height; allow closer to square
      let maxHeightFraction: CGFloat = 0.9 // allow tall boxes
      let maxAreaFraction: CGFloat = 0.8   // allow large area

      // Best box that passes geometry filters + primary threshold
      var bestBox: NormalizedBox?
      var bestConf: Float = 0.0

      // Best raw fish candidate (ignores geometry filters and threshold)
      var bestRawFishBox: NormalizedBox?
      var bestRawFishConf: Float = 0.0

      for i in 0 ..< numAnchors {
        // 1) Find best class & score for this anchor
        var bestClassIdx = -1
        var bestClassScore: Float = 0.0

        for c in 0 ..< numClasses {
          let score = Float(read(4 + c, i))
          if score > bestClassScore {
            bestClassScore = score
            bestClassIdx = c
          }
        }

        // If this anchor's best class is fish, ALWAYS consider it for the raw fallback
        if bestClassIdx == fishClassIndex {
          if bestClassScore > bestRawFishConf {
            bestRawFishConf = bestClassScore

            let xRaw = CGFloat(read(0, i))
            let yRaw = CGFloat(read(1, i))
            let wRaw = CGFloat(read(2, i))
            let hRaw = CGFloat(read(3, i))

            bestRawFishBox = NormalizedBox(
              xCenter: xRaw,
              yCenter: yRaw,
              width: wRaw,
              height: hRaw,
              confidence: bestClassScore
            )
          }
        } else {
          // Best class not fish → no need to continue for primary candidate
          continue
        }

        // For the primary (filtered) candidate, also require a minimum confidence
        guard bestClassScore >= minPrimaryConfidence else { continue }

        // 3) Read box geometry for filtered path
        let x = CGFloat(read(0, i))
        let y = CGFloat(read(1, i))
        let w = CGFloat(read(2, i))
        let h = CGFloat(read(3, i))

        // DEBUG: Log first detection's raw values
        if i == 0 {
          AppLogging.log({ "DEBUG first anchor: x=\(x), y=\(y), w=\(w), h=\(h)" }, level: .debug, category: .ml)
        }

        // 4) Geometry filters
        let aspect = w / max(h, 1.0)
        let hFrac = h / imgH
        let areaFrac = (w * h) / (imgW * imgH)

        if aspect < minAspect { continue }
        if hFrac > maxHeightFraction { continue }
        if areaFrac > maxAreaFraction { continue }

        let box = NormalizedBox(
          xCenter: x,
          yCenter: y,
          width: w,
          height: h,
          confidence: bestClassScore
        )

        if bestClassScore > bestConf {
          bestConf = bestClassScore
          bestBox = box
        }
      }

      // Prefer geometry-filtered box
      if let best = bestBox {
        AppLogging.log({ "runFishDetector: best fish (filtered) conf = \(best.confidence), x=\(best.xCenter), y=\(best.yCenter), w = \(best.width), h = \(best.height)" }, level: .info, category: .ml)
        return best
      }

        // Fallback: best raw fish candidate (even if confidence < minPrimaryConfidence),
        // but only if it's at least *barely* confident.
        if let fallback = bestRawFishBox {
          if fallback.confidence >= 0.01 { // or 0.02 if you want to be stricter
            AppLogging.log({ "runFishDetector: using raw fish box without geometry filters, conf = \(fallback.confidence), w = \(fallback.width), h = \(fallback.height)" }, level: .warn, category: .ml)
            return fallback
          } else {
            AppLogging.log({ "runFishDetector: best fish candidate too low-confidence (conf=\(fallback.confidence)); treating as no detection." }, level: .warn, category: .ml)
          }
        }

      AppLogging.log("runFishDetector: no fish boxes at all (model never preferred fish for any anchor).", level: .warn, category: .ml)
      return nil
    }

  /// Turn the best detected box into a rough length estimate.
  private func estimateLength(
    from box: NormalizedBox,
    imageSize: CGSize
  ) -> (inches: Double, display: String) {
    // YOLOv8 export is giving us pixel coordinates in 640×640 space.
    // Use the *long side* of the box as a proxy for fish length.
    var pixelLength = max(box.width, box.height)

    // Scale down boxes (training data has boxes around person+fish, not just fish)
    let env = AppEnvironment.shared
    pixelLength *= env.fishBoxScaleFactor

    // Heuristic: pixels per inch in the 640×640 model space
    let pixelsPerInch: CGFloat = env.fishPixelsPerInch
    let rawInches = Double(pixelLength / pixelsPerInch)

    AppLogging.log({ "estimateLength: w=\(box.width), h=\(box.height), pixelLength=\(pixelLength), rawInches=\(rawInches)" }, level: .debug, category: .ml)

    // Clamp to a plausible range for steelhead
    let clamped = max(env.fishMinLengthInches, min(rawInches, env.fishMaxLengthInches))

    let low = clamped * env.fishEstimateLowFactor
    let high = clamped * env.fishEstimateHighFactor

    let display = String(
      format: "%.0f–%.0f inches (photo estimate)",
      low.rounded(),
      high.rounded()
    )

    return (inches: clamped, display: display)
  }
}

// MARK: - MLFeatureProvider wrapper for ViT input (species)

private final class ViTInputFeatureProvider: MLFeatureProvider {
  private let imageArray: MLMultiArray

  init(imageArray: MLMultiArray) {
    self.imageArray = imageArray
  }

  var featureNames: Set<String> {
    ["image"]
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    if featureName == "image" {
      return MLFeatureValue(multiArray: imageArray)
    }
    return nil
  }
}

// MARK: - Helpers at file scope

private extension MLMultiArray {
  subscript(_ i: Int, _ j: Int, _ k: Int) -> Double {
    let idx: [NSNumber] = [
      NSNumber(value: i),
      NSNumber(value: j),
      NSNumber(value: k)
    ]
    return self[idx].doubleValue
  }
}

private extension CGImage {
  func toPixelBuffer(targetSize: CGSize) -> CVPixelBuffer? {
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(targetSize.width),
      Int(targetSize.height),
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pb, [])
    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(pb),
      width: Int(targetSize.width),
      height: Int(targetSize.height),
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else {
      CVPixelBufferUnlockBaseAddress(pb, [])
      return nil
    }

    context.draw(self, in: CGRect(origin: .zero, size: targetSize))
    CVPixelBufferUnlockBaseAddress(pb, [])

    return pb
  }
}
