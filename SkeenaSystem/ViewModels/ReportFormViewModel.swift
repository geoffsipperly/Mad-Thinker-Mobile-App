// Bend Fly Shop

import Combine
import CoreData
import CoreLocation
import SwiftUI

final class ReportFormViewModel: ObservableObject {
  // MARK: - Required for save & upload

  @Published var river: String = AppEnvironment.shared.defaultRiver
  @Published var species: String = ""
  @Published var sex: String = ""
  @Published var origin: String = "" // "Wild" | "Hatchery"
  @Published var lengthInches: Int = 0
  @Published var quality: String = ""
  @Published var tactic: String = "Swinging"
  @Published var guideName: String = ""
  @Published var clientName: String = ""
  @Published var anglerNumber: String = "" // REQUIRED in catch payload

  // MARK: - Optional

  @Published var tagId: String = "" // required only when origin == "Hatchery"
  @Published var notes: String = ""
  @Published var photo: UIImage?
  @Published var photoPath: String? // full file path to persist in Core Data
  @Published var classifiedWatersLicenseNumber: String? // OPTIONAL in catch payload

  // MARK: - UI

  @Published var isSaving: Bool = false
  @Published var showToast: Bool = false
  @Published var toastMessage: String = ""

  // MARK: - Location (provided by LocationManager)

  var currentLocation: CLLocation?

  // Match view’s length picker
  let lengths: [Int] = Array(20 ... 45)

  // MARK: - Validation (explicit; licences optional)

  var isValid: Bool {
    let requiredFilled =
      !river.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !sex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      lengthInches > 0 &&
      !quality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !tactic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !guideName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    let tagOK = (origin != "Hatchery") ||
      !tagId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    return requiredFilled && tagOK
  }

  // MARK: - Reset after save

  func reset() {
    species = ""
    sex = ""
    origin = ""
    lengthInches = 0
    quality = ""
    tagId = ""
    notes = ""
    photo = nil
    photoPath = nil
    classifiedWatersLicenseNumber = nil
    // Keep river/guide/tactic defaults; the view re-selects client/angler
  }

  // MARK: - Save -> Core Data

  func save(context: NSManagedObjectContext, trip: Trip?, onDone: @escaping (Bool) -> Void) {
    guard isValid else { onDone(false); return }
    isSaving = true

    let reportId = UUID()

    var resolvedPhotoPath: String?
    if let image = photo {
      do {
        // Store as a stable filename; PhotoStore keeps it in Documents/CatchPhotos
        let name = try PhotoStore.shared.save(
          image: image,
          preferredName: "catch-\(reportId.uuidString).jpg",
          quality: AppEnvironment.shared.imageCompressionQuality
        )
        resolvedPhotoPath = name // store the filename (recommended)
      } catch {
        print("[ReportFormVM] Photo save failed: \(error)")
        resolvedPhotoPath = nil
      }
    } else if let existing = photoPath, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      // If the VM already had a stored filename (e.g., coming back to edit before save)
      resolvedPhotoPath = existing
    }

    let lat = currentLocation?.coordinate.latitude
    let lon = currentLocation?.coordinate.longitude

    do {
      let created = try CatchReport.create(
        in: context,
        reportId: reportId,
        river: river,
        species: species,
        sex: sex,
        origin: origin,
        tagId: origin == "Hatchery" && !tagId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tagId : nil,
        lengthInches: lengthInches,
        quality: quality,
        tactic: tactic,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        photoPath: resolvedPhotoPath,
        latitude: lat,
        longitude: lon,
        createdAt: Date(),
        guideName: guideName,
        clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clientName,
        status: "Saved locally"
      )
      created.trip = trip

      // write new fields (unchanged)
      created.setValue(anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anglerNumber")
      if let lic = classifiedWatersLicenseNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !lic.isEmpty {
        created.setValue(lic, forKey: "classifiedWatersLicenseNumber")
      } else {
        created.setValue(nil, forKey: "classifiedWatersLicenseNumber")
      }

      try context.save()
      toast("Report saved locally")
      reset()
      isSaving = false
      onDone(true) // ✅ notify success
    } catch {
      toast("Failed to save report")
      isSaving = false
      onDone(false) // notify failure
    }
  }

  // MARK: - Toast

  private func toast(_ message: String) {
    toastMessage = message
    withAnimation { showToast = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      withAnimation { self.showToast = false }
    }
  }
}
