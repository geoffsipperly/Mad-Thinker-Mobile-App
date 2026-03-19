// Bend Fly Shop

import CoreLocation
import CoreML
#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif
import UIKit
import Vision

/// How the length estimate was produced.
enum LengthEstimateSource: String, Codable {
  case regressor  // ML model prediction
  case heuristic  // pixel-based heuristic
  case manual     // user correction
}

struct CatchPhotoAnalysis {
  let riverName: String?
  let species: String?
  let sex: String?
  let estimatedLength: String?
  let lifecycleStage: String?
  let featureVector: CatchPhotoAnalyzer.LengthFeatureVector?
  let lengthSource: LengthEstimateSource?
  let modelVersion: String?

  init(
    riverName: String?,
    species: String?,
    sex: String?,
    estimatedLength: String?,
    lifecycleStage: String? = nil,
    featureVector: CatchPhotoAnalyzer.LengthFeatureVector? = nil,
    lengthSource: LengthEstimateSource? = nil,
    modelVersion: String? = nil
  ) {
    self.riverName = riverName
    self.species = species
    self.sex = sex
    self.estimatedLength = estimatedLength
    self.lifecycleStage = lifecycleStage
    self.featureVector = featureVector
    self.lengthSource = lengthSource
    self.modelVersion = modelVersion
  }
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
    let vitResult = runViT(on: image)

    let speciesText: String?
    if let vit = vitResult,
       vit.index >= 0,
       vit.index < speciesLabels.count {
      let rawLabel = speciesLabels[vit.index]
      let prettyLabel = rawLabel.replacingOccurrences(of: "_", with: " ")

      speciesText = "Species (model): \(prettyLabel)"
      AppLogging.log({ "ViT species: \(prettyLabel), confidence: \(vit.confidence)" }, level: .info, category: .ml)
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

    // 4. Hand pose detection via MediaPipe
    let handMeasurement = detectHand(on: image)

    // 5. Detection + length estimation
    var lengthText: String? = "Length estimate not available (photo estimate failed)"
    var featureVector: LengthFeatureVector?
    var lengthSource: LengthEstimateSource?

    let detection = runDetector(on: image)

    if let fishBox = detection.fishBox {
      AppLogging.log({ "Detector found fish box with conf \(fishBox.confidence)" }, level: .info, category: .ml)

      if let personBox = detection.personBox {
        AppLogging.log({ "Detector found person box with conf \(personBox.confidence)" }, level: .info, category: .ml)
      }

      // Build feature vector from all detection results
      let speciesIdx = vitResult?.index ?? 0
      let speciesConf = vitResult?.confidence ?? 0.0

      let fv = buildFeatureVector(
        fishBox: fishBox,
        personBox: detection.personBox,
        speciesIndex: speciesIdx,
        speciesConfidence: speciesConf,
        hand: handMeasurement,
        imageSize: image.size
      )
      featureVector = fv
      AppLogging.log({ "Built feature vector: personDetected=\(fv.personBoxHeight > 0), handDetected=\(fv.handDetected > 0), species=\(Int(fv.speciesIndex))" }, level: .debug, category: .ml)

      // Log feature breakdown grouped by signal source
      AppLogging.log({
        var lines = ["── Feature Vector Breakdown ──"]

        // Fish detection
        lines.append("  Fish: \(String(format: "%.0f", fv.fishBoxWidth))×\(String(format: "%.0f", fv.fishBoxHeight))px, " +
                      "area=\(String(format: "%.0f", fv.fishBoxArea)), " +
                      "aspect=\(String(format: "%.2f", fv.fishAspectRatio)), " +
                      "conf=\(String(format: "%.2f", fv.fishConfidence)), " +
                      "pixelLen=\(String(format: "%.0f", fv.fishPixelLength))")

        // Person reference (primary scale signal)
        if fv.personBoxHeight > 0 {
          lines.append("  Person: \(String(format: "%.0f", fv.personBoxWidth))×\(String(format: "%.0f", fv.personBoxHeight))px, " +
                        "fish/person=\(String(format: "%.3f", fv.fishToPersonRatio))")
          lines.append("  Person ratios: w/h=\(String(format: "%.3f", fv.fishWToPersonH)), " +
                        "h/h=\(String(format: "%.3f", fv.fishHToPersonH)), " +
                        "w/w=\(String(format: "%.3f", fv.fishWToPersonW)), " +
                        "area/h²=\(String(format: "%.3f", fv.fishAreaToPersonHSq))")
        } else {
          lines.append("  Person: NOT DETECTED (ratios zeroed)")
        }

        // Hand/finger reference (secondary scale signal)
        if fv.handDetected > 0 {
          lines.append("  Hand: fingerW=\(String(format: "%.1f", fv.fingerWidthPx))px, " +
                        "fingerL=\(String(format: "%.1f", fv.fingerLengthPx))px, " +
                        "ppi=\(String(format: "%.1f", fv.ppiFromFinger))")
          lines.append("  Hand ratios: fish/fingerW=\(String(format: "%.1f", fv.fishToFingerWidth)), " +
                        "fish/fingerL=\(String(format: "%.1f", fv.fishToFingerLength)), " +
                        "inches_from_finger=\(String(format: "%.1f", fv.fishInchesFromFinger))")
        } else {
          lines.append("  Hand: NOT DETECTED (finger features zeroed)")
        }

        // Species + image context
        lines.append("  Species: idx=\(Int(fv.speciesIndex)), conf=\(String(format: "%.2f", fv.speciesConfidence)), " +
                      "diagFrac=\(String(format: "%.3f", fv.diagonalFraction))")

        return lines.joined(separator: "\n")
      }, level: .debug, category: .ml)

      // Try ML regressor first (if enabled), fall back to heuristic
      if AppEnvironment.shared.useLengthRegressor, let predicted = predictLength(from: fv) {
        let clamped = max(
          AppEnvironment.shared.fishMinLengthInches,
          min(predicted, AppEnvironment.shared.fishMaxLengthInches)
        )
        lengthText = String(format: "%.0f inches (ML estimate)", clamped.rounded())
        lengthSource = .regressor
        AppLogging.log({ "Length regressor: raw=\(String(format: "%.1f", predicted)), clamped=\(String(format: "%.1f", clamped))" }, level: .debug, category: .ml)

        // Heuristic confidence based on available scale signals
        let confidence = Self.estimateConfidence(from: fv)
        AppLogging.log({
          "Length estimate confidence: \(confidence.label) (\(String(format: "%.0f", confidence.score * 100))%) — \(confidence.reasoning)"
        }, level: .info, category: .ml)
      } else {
        let result = estimateLength(from: fishBox, imageSize: image.size)
        lengthText = result.display
        lengthSource = .heuristic
        AppLogging.log({ "Length heuristic fallback: \(result.display) (regressor \(AppEnvironment.shared.useLengthRegressor ? "failed" : "disabled"))" }, level: .debug, category: .ml)
      }
    } else {
      AppLogging.log("Detector did not return any fish box above confidence/shape thresholds.", level: .warn, category: .ml)
    }

    return CatchPhotoAnalysis(
      riverName: riverDisplay,
      species: speciesText,
      sex: sexText,
      estimatedLength: lengthText,
      featureVector: featureVector,
      lengthSource: lengthSource,
      modelVersion: CatchPhotoAnalyzer._lengthRegressorVersion
    )
  }

  // MARK: - ViT inference (species)

  /// Runs the ViT species model on a UIImage and returns the best species index + softmax confidence.
  private func runViT(on image: UIImage) -> (index: Int, confidence: Float)? {
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

    guard let bestIdx = argmax(logits) else { return nil }

    // Compute softmax confidence for the winning class
    let confidence = softmaxConfidence(logits, at: bestIdx)

    return (index: bestIdx, confidence: confidence)
  }

  /// Computes the softmax probability for a specific index in a logits array.
  private func softmaxConfidence(_ logits: MLMultiArray, at index: Int) -> Float {
    // Find max for numerical stability
    var maxVal: Float = -.greatestFiniteMagnitude
    for i in 0 ..< logits.count {
      maxVal = max(maxVal, logits[i].floatValue)
    }

    // Compute exp(logit - max) and sum
    var sumExp: Float = 0.0
    var targetExp: Float = 0.0
    for i in 0 ..< logits.count {
      let e = exp(logits[i].floatValue - maxVal)
      sumExp += e
      if i == index {
        targetExp = e
      }
    }

    return targetExp / sumExp
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

  // MARK: - Hand pose detection (MediaPipe)

  /// Finger measurements from MediaPipe hand detection, in original image pixel space.
  struct HandMeasurement {
    let fingerWidthPx: Float   // index-to-middle knuckle distance
    let fingerLengthPx: Float  // index MCP to tip distance
    let confidence: Float      // handedness confidence
  }

  /// Detects hand landmarks via MediaPipe and returns finger measurements for the best hand.
  /// Applies same sanity filters as the Python training pipeline.
  private func detectHand(on image: UIImage) -> HandMeasurement? {
    #if canImport(MediaPipeTasksVision)
    guard let cgImage = image.cgImage else { return nil }

    let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task")
    guard let modelPath else {
      AppLogging.log("detectHand: hand_landmarker.task not found in bundle", level: .error, category: .ml)
      return nil
    }

    let options = HandLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.numHands = 2
    options.minHandDetectionConfidence = 0.3
    options.minHandPresenceConfidence = 0.3
    options.runningMode = .image

    guard let landmarker = try? HandLandmarker(options: options) else {
      AppLogging.log("detectHand: failed to create HandLandmarker", level: .error, category: .ml)
      return nil
    }

    let mpImage = try? MPImage(uiImage: image)
    guard let mpImage else {
      AppLogging.log("detectHand: failed to create MPImage", level: .error, category: .ml)
      return nil
    }

    guard let result = try? landmarker.detect(image: mpImage) else {
      AppLogging.log("detectHand: detection failed", level: .error, category: .ml)
      return nil
    }

    guard !result.landmarks.isEmpty else {
      AppLogging.log("detectHand: no hands detected", level: .debug, category: .ml)
      return nil
    }

    let imgW = Float(image.size.width)
    let imgH = Float(image.size.height)

    var bestMeasurement: HandMeasurement?
    var bestConf: Float = 0.0

    for (i, hand) in result.landmarks.enumerated() {
      guard hand.count > 9 else { continue }

      // Key landmarks (same indices as Python)
      let idxMCP = hand[5]  // Index finger knuckle
      let idxTip = hand[8]  // Index fingertip
      let midMCP = hand[9]  // Middle finger knuckle

      // Finger width: index-to-middle knuckle distance (pixels)
      let fingerWidthPx = sqrtf(
        powf((idxMCP.x - midMCP.x) * imgW, 2) +
        powf((idxMCP.y - midMCP.y) * imgH, 2)
      )

      // Index finger length: knuckle to tip (pixels)
      let fingerLengthPx = sqrtf(
        powf((idxMCP.x - idxTip.x) * imgW, 2) +
        powf((idxMCP.y - idxTip.y) * imgH, 2)
      )

      // Handedness confidence
      let conf: Float = if i < result.handedness.count, !result.handedness[i].isEmpty {
        result.handedness[i][0].score
      } else {
        0.5
      }

      // ── Sanity filters (matching Python pipeline) ──

      // Min pixel size
      if fingerWidthPx < 10 || fingerLengthPx < 15 { continue }

      // Length-to-width ratio must be plausible (1.5-10x)
      let lengthToWidth = fingerLengthPx / max(fingerWidthPx, 1)
      if lengthToWidth < 1.5 || lengthToWidth > 10.0 { continue }

      // PPI sanity: finger width ~0.85" real-world
      let ppi = fingerWidthPx / 0.85
      if ppi < 10 || ppi > 500 { continue }

      // Implied max fish length sanity
      let imgDiag = sqrtf(imgW * imgW + imgH * imgH)
      let maxFishInches = imgDiag / ppi
      if maxFishInches < 5 || maxFishInches > 80 { continue }

      if conf > bestConf {
        bestConf = conf
        bestMeasurement = HandMeasurement(
          fingerWidthPx: fingerWidthPx,
          fingerLengthPx: fingerLengthPx,
          confidence: conf
        )
      }
    }

    if let m = bestMeasurement {
      AppLogging.log({ "detectHand: fingerWidth=\(m.fingerWidthPx)px, fingerLength=\(m.fingerLengthPx)px, conf=\(m.confidence)" }, level: .info, category: .ml)
    } else {
      AppLogging.log("detectHand: all hands failed sanity filters", level: .debug, category: .ml)
    }

    return bestMeasurement
    #else
    AppLogging.log("detectHand: MediaPipeTasksVision not available, skipping hand detection", level: .info, category: .ml)
    return nil
    #endif
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

  // MARK: - Feature vector & length regressor

  /// The 26 features in exact order matching the Python FEATURE_COLS.
  /// This order is critical — a mismatch produces silently wrong predictions.
  static let featureCols: [String] = [
    // Base features (19)
    "fish_box_width",
    "fish_box_height",
    "fish_box_area",
    "fish_aspect_ratio",
    "fish_confidence",
    "person_box_height",
    "person_box_width",
    "person_aspect_ratio",
    "fish_to_person_ratio",
    "species_index",
    "species_confidence",
    "diagonal_fraction",
    "hand_detected",
    "finger_width_px",
    "finger_length_px",
    "ppi_from_finger",
    "fish_to_finger_width",
    "fish_to_finger_length",
    "fish_inches_from_finger",
    // Engineered features (7)
    "fish_pixel_length",
    "pixel_length_to_person",
    "fish_w_to_person_h",
    "fish_h_to_person_h",
    "fish_area_to_person_h_sq",
    "fish_w_to_person_w",
    "fish_area_to_person_w_sq",
  ]

  /// All 26 features for the length regressor, in FEATURE_COLS order. Codable for upload to Supabase.
  struct LengthFeatureVector: Codable {
    // Base features
    let fishBoxWidth: Double
    let fishBoxHeight: Double
    let fishBoxArea: Double
    let fishAspectRatio: Double
    let fishConfidence: Double
    let personBoxHeight: Double
    let personBoxWidth: Double
    let personAspectRatio: Double
    let fishToPersonRatio: Double
    let speciesIndex: Double
    let speciesConfidence: Double
    let diagonalFraction: Double
    let handDetected: Double
    let fingerWidthPx: Double
    let fingerLengthPx: Double
    let ppiFromFinger: Double
    let fishToFingerWidth: Double
    let fishToFingerLength: Double
    let fishInchesFromFinger: Double
    // Engineered features
    let fishPixelLength: Double
    let pixelLengthToPerson: Double
    let fishWToPersonH: Double
    let fishHToPersonH: Double
    let fishAreaToPersonHSq: Double
    let fishWToPersonW: Double
    let fishAreaToPersonWSq: Double

    /// Returns values as a Double array in FEATURE_COLS order.
    var asArray: [Double] {
      [
        fishBoxWidth, fishBoxHeight, fishBoxArea, fishAspectRatio, fishConfidence,
        personBoxHeight, personBoxWidth, personAspectRatio, fishToPersonRatio,
        speciesIndex, speciesConfidence, diagonalFraction,
        handDetected, fingerWidthPx, fingerLengthPx, ppiFromFinger,
        fishToFingerWidth, fishToFingerLength, fishInchesFromFinger,
        fishPixelLength, pixelLengthToPerson,
        fishWToPersonH, fishHToPersonH, fishAreaToPersonHSq,
        fishWToPersonW, fishAreaToPersonWSq,
      ]
    }
  }

  /// Builds the 26-feature vector from detection results.
  /// Matches Python `compute_features()` + `add_engineered_features()` exactly.
  private func buildFeatureVector(
    fishBox: NormalizedBox,
    personBox: NormalizedBox?,
    speciesIndex: Int,
    speciesConfidence: Float,
    hand: HandMeasurement?,
    imageSize: CGSize
  ) -> LengthFeatureVector {
    let imgSize: Double = 640.0 // YOLO model input size

    let fw = Double(fishBox.width)
    let fh = Double(fishBox.height)
    let fishArea = fw * fh

    // Person features (zero if no person detected)
    let pH = personBox.map { Double($0.height) } ?? 0.0
    let pW = personBox.map { Double($0.width) } ?? 0.0
    let personAR = pW / max(pH, 1.0)
    let fishToPersonR = personBox != nil ? max(fw, fh) / pH : 0.0

    // Diagonal fraction
    let diagonal = sqrt(fw * fw + fh * fh)
    let frameDiagonal = sqrt(imgSize * imgSize + imgSize * imgSize)
    let diagFraction = diagonal / frameDiagonal

    // Hand features (zero if no hand detected)
    let handDet: Double = hand != nil ? 1.0 : 0.0
    let fwPx = Double(hand?.fingerWidthPx ?? 0)
    let flPx = Double(hand?.fingerLengthPx ?? 0)
    let ppi = fwPx > 0 ? fwPx / 0.85 : 0.0

    // Fish pixel length in original image space (for finger-based ratios)
    let origW = Double(imageSize.width)
    let origH = Double(imageSize.height)
    let fishPixelOrig = max(fw / (imgSize / origW), fh / (imgSize / origH))
    let fishToFingerW = fwPx > 0 ? fishPixelOrig / fwPx : 0.0
    let fishToFingerL = flPx > 0 ? fishPixelOrig / flPx : 0.0
    let fishInchesFromF = ppi > 0 ? fishPixelOrig / ppi : 0.0

    // Engineered features
    let fishPixelLength = max(fw, fh)
    let clampedPH = max(pH, 1.0)
    let clampedPW = max(pW, 1.0)

    return LengthFeatureVector(
      fishBoxWidth: fw,
      fishBoxHeight: fh,
      fishBoxArea: fishArea,
      fishAspectRatio: fw / max(fh, 1.0),
      fishConfidence: Double(fishBox.confidence),
      personBoxHeight: pH,
      personBoxWidth: pW,
      personAspectRatio: personAR,
      fishToPersonRatio: fishToPersonR,
      speciesIndex: Double(speciesIndex),
      speciesConfidence: Double(speciesConfidence),
      diagonalFraction: diagFraction,
      handDetected: handDet,
      fingerWidthPx: fwPx,
      fingerLengthPx: flPx,
      ppiFromFinger: ppi,
      fishToFingerWidth: fishToFingerW,
      fishToFingerLength: fishToFingerL,
      fishInchesFromFinger: fishInchesFromF,
      fishPixelLength: fishPixelLength,
      pixelLengthToPerson: fishPixelLength / clampedPH,
      fishWToPersonH: fw / clampedPH,
      fishHToPersonH: fh / clampedPH,
      fishAreaToPersonHSq: fishArea / (clampedPH * clampedPH),
      fishWToPersonW: fw / clampedPW,
      fishAreaToPersonWSq: fishArea / (clampedPW * clampedPW)
    )
  }

  /// Cached length regressor model
  private static var _lengthRegressor: MLModel?
  /// Cached model version string read from CoreML metadata
  private static var _lengthRegressorVersion: String?

  /// Runs the LengthRegressor CoreML model on a feature vector.
  /// Returns predicted length in inches, or nil on failure.
  private func predictLength(from features: LengthFeatureVector) -> Double? {
    // Lazy-load the model
    if CatchPhotoAnalyzer._lengthRegressor == nil {
      guard let url = Bundle.main.url(forResource: "LengthRegressor", withExtension: "mlmodelc") else {
        AppLogging.log("predictLength: LengthRegressor.mlmodelc not found in bundle", level: .error, category: .ml)
        return nil
      }
      let model = try? MLModel(contentsOf: url)
      CatchPhotoAnalyzer._lengthRegressor = model
      // Extract version from model metadata (set during training via coremltools)
      let metadata = model?.modelDescription.metadata
      let version = (metadata?[.versionString] as? String)
        ?? (metadata?[.description] as? String)
        ?? "unknown"
      CatchPhotoAnalyzer._lengthRegressorVersion = version
      AppLogging.log("LengthRegressor loaded, model version: \(version)", level: .info, category: .ml)
    }

    guard let model = CatchPhotoAnalyzer._lengthRegressor else {
      AppLogging.log("predictLength: failed to load LengthRegressor model", level: .error, category: .ml)
      return nil
    }

    // Build MLDictionaryFeatureProvider with named Double inputs
    let values = features.asArray
    var featureDict: [String: MLFeatureValue] = [:]
    for (i, name) in Self.featureCols.enumerated() {
      featureDict[name] = MLFeatureValue(double: values[i])
    }

    guard let provider = try? MLDictionaryFeatureProvider(dictionary: featureDict) else {
      AppLogging.log("predictLength: failed to create feature provider", level: .error, category: .ml)
      return nil
    }

    guard let output = try? model.prediction(from: provider) else {
      AppLogging.log("predictLength: model prediction failed", level: .error, category: .ml)
      return nil
    }

    guard let lengthValue = output.featureValue(for: "length_inches") else {
      AppLogging.log("predictLength: output missing 'length_inches' feature", level: .error, category: .ml)
      return nil
    }

    let predicted = lengthValue.doubleValue
    let ver = CatchPhotoAnalyzer._lengthRegressorVersion ?? "unknown"
    AppLogging.log({ "predictLength: predicted \(predicted) inches (model version: \(ver))" }, level: .info, category: .ml)
    return predicted
  }

  // MARK: - Confidence estimation

  struct ConfidenceEstimate {
    let score: Double   // 0.0–1.0
    let label: String   // "High", "Medium", "Low"
    let reasoning: String
  }

  /// Heuristic confidence score based on which scale signals the model had available.
  /// This doesn't reflect the model's internal certainty — it scores input quality.
  static func estimateConfidence(from fv: LengthFeatureVector) -> ConfidenceEstimate {
    var score: Double = 0.0
    var factors: [String] = []

    // Fish detection quality (0–25 pts)
    let fishConf = Double(fv.fishConfidence)
    if fishConf >= 0.7 {
      score += 0.25
      factors.append("strong fish detection (\(String(format: "%.0f", fishConf * 100))%)")
    } else if fishConf >= 0.4 {
      score += 0.15
      factors.append("moderate fish detection (\(String(format: "%.0f", fishConf * 100))%)")
    } else {
      score += 0.05
      factors.append("weak fish detection (\(String(format: "%.0f", fishConf * 100))%)")
    }

    // Person reference — primary scale signal (0–35 pts)
    if fv.personBoxHeight > 0 {
      // Person detected: score based on fish-to-person ratio plausibility
      let ratio = fv.fishToPersonRatio
      if ratio > 0.1 && ratio < 1.5 {
        score += 0.35
        factors.append("person reference (ratio \(String(format: "%.2f", ratio)))")
      } else {
        score += 0.15
        factors.append("person detected but unusual ratio (\(String(format: "%.2f", ratio)))")
      }
    } else {
      factors.append("no person reference")
    }

    // Hand/finger reference — secondary scale signal (0–25 pts)
    if fv.handDetected > 0 {
      let ppi = fv.ppiFromFinger
      if ppi > 20 && ppi < 200 {
        score += 0.25
        factors.append("hand calibration (ppi=\(String(format: "%.0f", ppi)))")
      } else {
        score += 0.10
        factors.append("hand detected but unusual ppi (\(String(format: "%.0f", ppi)))")
      }
    } else {
      factors.append("no hand reference")
    }

    // Species confidence (0–10 pts)
    let specConf = Double(fv.speciesConfidence)
    if specConf >= 0.7 {
      score += 0.10
      factors.append("confident species ID")
    } else if specConf >= 0.4 {
      score += 0.05
      factors.append("uncertain species ID")
    }

    // Image composition (0–5 pts)
    if fv.diagonalFraction > 0.15 && fv.diagonalFraction < 0.7 {
      score += 0.05
      factors.append("good framing")
    }

    let label: String
    switch score {
    case 0.70...: label = "High"
    case 0.45...: label = "Medium"
    default:      label = "Low"
    }

    return ConfidenceEstimate(
      score: min(score, 1.0),
      label: label,
      reasoning: factors.joined(separator: ", ")
    )
  }

  // MARK: - Detector helpers (YOLOv8 → length)

  private struct NormalizedBox {
    let xCenter: CGFloat // pixels in 640×640 coordinate space
    let yCenter: CGFloat // pixels in 640×640 coordinate space
    let width: CGFloat   // pixels in 640×640 coordinate space
    let height: CGFloat  // pixels in 640×640 coordinate space
    let confidence: Float
  }

  /// Result from YOLO detector containing the best fish and person boxes.
  private struct DetectionResult {
    let fishBox: NormalizedBox?
    let personBox: NormalizedBox?
  }
    
    /// Runs the YOLOv8 detector and returns the highest-confidence fish and person boxes.
    /// Handles both [1, C, A] and [1, A, C] output layouts (C = 4 + numClasses, A = anchors).
    private func runDetector(on image: UIImage) -> DetectionResult {
      guard let cgImage = image.cgImage else {
        AppLogging.log("runDetector: could not get CGImage from UIImage", level: .error, category: .ml)
        return DetectionResult(fishBox: nil, personBox: nil)
      }

      // YOLOv8 CoreML export expects 640×640
      let inputSize = CGSize(width: 640, height: 640)

      guard let pixelBuffer = cgImage.toPixelBuffer(targetSize: inputSize) else {
        AppLogging.log("runDetector: failed to create pixel buffer", level: .error, category: .ml)
        return DetectionResult(fishBox: nil, personBox: nil)
      }

      guard let output = try? detectorModel.prediction(image: pixelBuffer) else {
        AppLogging.log("runDetector: model prediction failed", level: .error, category: .ml)
        return DetectionResult(fishBox: nil, personBox: nil)
      }

      let arr = output.var_913

      guard arr.shape.count == 3,
            arr.shape[0].intValue == 1 else {
        AppLogging.log({ "runDetector: unexpected output shape \(arr.shape)" }, level: .error, category: .ml)
        return DetectionResult(fishBox: nil, personBox: nil)
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
        AppLogging.log({ "runDetector: not enough channels (\(channels)) for xywh+classes" }, level: .error, category: .ml)
        return DetectionResult(fishBox: nil, personBox: nil)
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

      AppLogging.log({ "runDetector: output shape=\(arr.shape), channels=\(channels), anchors=\(numAnchors), channelsOnSecondAxis=\(channelsOnSecondAxis)" }, level: .debug, category: .ml)

      // data.yaml: names: ['fish', 'person'] → fish = class 0, person = class 1
      let fishClassIndex = 0
      let personClassIndex = 1

      // Threshold for our "good" candidate (geometry-filtered)
      let minPrimaryConfidence: Float = AppEnvironment.shared.fishDetectMinConfidence

      // Geometry thresholds
      let imgW: CGFloat = 640.0
      let imgH: CGFloat = 640.0
      let minAspect: CGFloat = 1.0        // width / height; allow closer to square
      let maxHeightFraction: CGFloat = 0.9 // allow tall boxes
      let maxAreaFraction: CGFloat = 0.8   // allow large area

      // Best fish box that passes geometry filters + primary threshold
      var bestBox: NormalizedBox?
      var bestConf: Float = 0.0

      // Best raw fish candidate (ignores geometry filters and threshold)
      var bestRawFishBox: NormalizedBox?
      var bestRawFishConf: Float = 0.0

      // Best person box (highest confidence, no geometry filters needed)
      var bestPersonBox: NormalizedBox?
      var bestPersonConf: Float = 0.0

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

        // Track person box (class 1) — highest confidence, no geometry filters
        if bestClassIdx == personClassIndex, bestClassScore > bestPersonConf {
          let xRaw = CGFloat(read(0, i))
          let yRaw = CGFloat(read(1, i))
          let wRaw = CGFloat(read(2, i))
          let hRaw = CGFloat(read(3, i))

          bestPersonConf = bestClassScore
          bestPersonBox = NormalizedBox(
            xCenter: xRaw,
            yCenter: yRaw,
            width: wRaw,
            height: hRaw,
            confidence: bestClassScore
          )
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
          // Best class not fish or person → skip primary fish candidate path
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

      // Log person detection result
      if let person = bestPersonBox {
        AppLogging.log({ "runDetector: best person conf = \(person.confidence), x=\(person.xCenter), y=\(person.yCenter), w=\(person.width), h=\(person.height)" }, level: .info, category: .ml)
      }

      // Resolve fish box: prefer geometry-filtered, then raw fallback
      let resolvedFishBox: NormalizedBox?

      if let best = bestBox {
        AppLogging.log({ "runDetector: best fish (filtered) conf = \(best.confidence), x=\(best.xCenter), y=\(best.yCenter), w = \(best.width), h = \(best.height)" }, level: .info, category: .ml)
        resolvedFishBox = best
      } else if let fallback = bestRawFishBox, fallback.confidence >= 0.01 {
        AppLogging.log({ "runDetector: using raw fish box without geometry filters, conf = \(fallback.confidence), w = \(fallback.width), h = \(fallback.height)" }, level: .warn, category: .ml)
        resolvedFishBox = fallback
      } else {
        if let fallback = bestRawFishBox {
          AppLogging.log({ "runDetector: best fish candidate too low-confidence (conf=\(fallback.confidence)); treating as no detection." }, level: .warn, category: .ml)
        } else {
          AppLogging.log("runDetector: no fish boxes at all (model never preferred fish for any anchor).", level: .warn, category: .ml)
        }
        resolvedFishBox = nil
      }

      return DetectionResult(fishBox: resolvedFishBox, personBox: bestPersonBox)
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
