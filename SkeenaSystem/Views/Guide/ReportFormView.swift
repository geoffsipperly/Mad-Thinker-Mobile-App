// Bend Fly Shop

import CoreData
import CoreLocation
import SwiftUI
import UIKit
import Photos

struct ReportFormView: View {
  @Environment(\.managedObjectContext) private var context
  @Environment(\.dismiss) private var dismiss

  @StateObject private var vm = ReportFormViewModel()
  @StateObject private var loc = LocationManager() // uses your existing manager

  // Trips (in-progress: started <= now AND (no end OR ends today-or-later))
  @FetchRequest private var trips: FetchedResults<Trip>

  // Selections & derived options
  @State private var selectedTripID: NSManagedObjectID?
  @State private var selectedClientID: NSManagedObjectID?
  @State private var clientOptions: [ClientOption] = []

  @State private var selectedLicenseID: NSManagedObjectID?
  @State private var licenseOptions: [LicenseOption] = []

  // Internals to wire to VM
  @State private var selectedClientAnglerNumber: String = "" // REQUIRED
  @State private var selectedLicenseNumber: String? // OPTIONAL

  private let speciesOptions = ["Steelhead", "Salmon", "Trout"]

  // Single, root-level media presenter
  private enum ActiveMediaPicker: Identifiable { case library, camera; var id: Int { self == .library ? 1 : 2 } }
  @State private var activePicker: ActiveMediaPicker?
  @State private var isPresentingPicker: Bool = false // guard to avoid concurrent presentations

  // MARK: - Init

  init() {
    let sort = [NSSortDescriptor(keyPath: \Trip.startDate, ascending: false)]

    let now = Date()
    let startOfToday = Calendar.current.startOfDay(for: now)
    // Use start-of-yesterday so same-day trips remain visible the next day
    // instead of vanishing once the calendar date rolls over.
    let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)!

    // Break the predicate into simple parts so the compiler is happy
    let started = NSPredicate(format: "startDate <= %@", now as NSDate)
    let openOrRecentlyEnded = NSPredicate(
      format: "endDate == nil OR endDate >= %@", startOfYesterday as NSDate
    )

    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      started, openOrRecentlyEnded
    ])

    _trips = FetchRequest(
      sortDescriptors: sort,
      predicate: predicate,
      animation: .default
    )
  }

  private func ensureCatchDefaults() {
    if vm.river.isEmpty { vm.river = "Nehalem" }
    if vm.species.isEmpty { vm.species = "Steelhead" }
    if vm.sex.isEmpty { vm.sex = "Female" }
    if vm.origin.isEmpty { vm.origin = "Wild" }
    if vm.lengthInches == 0 { vm.lengthInches = 30 }
    if vm.quality.isEmpty { vm.quality = "Strong" }
    if vm.tactic.isEmpty { vm.tactic = "Swinging" }
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      List {
        // Trip
        tripSection()
          .listRowBackground(Color.black)

        // Catch details
        catchDetailsSection()
          .listRowBackground(Color.black)

        // Classified license
        classifiedLicenseSection()
          .listRowBackground(Color.black)

        // Optional
        optionalSection()
          .listRowBackground(Color.black)

        // System
        systemSection()
          .listRowBackground(Color.black)

        // Save
        saveSection()
          .listRowBackground(Color.black)
      }
      .listStyle(.insetGrouped)
      .modifier(HideListBackgroundIfAvailable())
    }
    .navigationTitle("Record a Catch")
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          dismiss()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.backward")
            Text("Back")
          }
        }
      }
    }
    .environment(\.colorScheme, .dark)
  }

  // MARK: - Sections

  @ViewBuilder private func tripSection() -> some View {
    Section(header: Text("Trip").foregroundColor(.white)) {
      Picker("Trip", selection: $selectedTripID) {
        Text("Select").tag(NSManagedObjectID?(nil))
        ForEach(trips) { t in Text(tripDisplay(t)).tag(Optional(t.objectID)) }
      }

      HStack {
        Text("Guide Name")
        Spacer()
        Text(selectedTrip?.guideName ?? "—").foregroundColor(.secondary)
      }

      Picker("Angler Name", selection: $selectedClientID) {
        Text("Select").tag(NSManagedObjectID?(nil))
        ForEach(clientOptions) { option in Text(option.name).tag(Optional(option.id)) }
      }

      // Readonly badge showing the angler number that will be saved
      HStack {
        Text("Angler Number")
        Spacer()
        Text(selectedClientAnglerNumber.isEmpty ? "—" : selectedClientAnglerNumber)
          .foregroundColor(selectedClientAnglerNumber.isEmpty ? .secondary : .primary)
      }
    }
  }

  @ViewBuilder private func catchDetailsSection() -> some View {
    Section(header: Text("Catch Details").foregroundColor(.white)) {
      Picker("River", selection: $vm.river) {
        Text("Nehalem").tag("Nehalem")
        Text("Wilson").tag("Wilson")
        Text("Trask").tag("Trask")
        Text("Nestucca").tag("Nestucca")
        Text("Kilchis").tag("Kilchis")
      }
      .pickerStyle(.segmented)

      Picker("Species", selection: $vm.species) {
        ForEach(speciesOptions, id: \.self) { Text($0).tag($0) }
      }

      Picker("Sex", selection: $vm.sex) {
        Text("Select").tag("")
        Text("Male").tag("Male")
        Text("Female").tag("Female")
      }

      Picker("Origin", selection: $vm.origin) {
        Text("Select").tag("")
        Text("Wild").tag("Wild")
        Text("Hatchery").tag("Hatchery")
      }

      if vm.origin == "Hatchery" {
        TextField("Tag ID", text: $vm.tagId)
          .textInputAutocapitalization(.characters)
          // .disableAutorrection(true)
      }

      Picker("Estimated Length (in)", selection: $vm.lengthInches) {
        ForEach(vm.lengths, id: \.self) { Text("\($0)").tag($0) }
      }

      Picker("Quality", selection: $vm.quality) {
        Text("Select").tag("")
        Text("Strong").tag("Strong")
        Text("Moderate").tag("Moderate")
        Text("Weak").tag("Weak")
      }

      Picker("Tactic", selection: $vm.tactic) {
        Text("Swinging").tag("Swinging")
        Text("Nymphing").tag("Nymphing")
        Text("Drys").tag("Drys")
      }.pickerStyle(.segmented)
    }
  }

  @ViewBuilder private func classifiedLicenseSection() -> some View {
    Section(header: Text("Classified Licence").foregroundColor(.white)) {
      if selectedClientID == nil {
        Text("Select an angler to view licences.").foregroundColor(.secondary)
      } else if licenseOptions.isEmpty {
        Text("No classified licences found for this angler.").foregroundColor(.secondary)
      } else {
        Picker("Licence", selection: $selectedLicenseID) {
          Text("No Valid Licence").tag(NSManagedObjectID?(nil))
          ForEach(licenseOptions) { opt in Text(opt.display).tag(Optional(opt.id)) }
        }
        .onChange(of: selectedLicenseID) { _ in
          if let licID = selectedLicenseID,
             let lic = try? context.existingObject(with: licID) as? ClassifiedWaterLicense {
            selectedLicenseNumber = lic.licNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            vm.classifiedWatersLicenseNumber = selectedLicenseNumber
          } else {
            selectedLicenseNumber = nil
            vm.classifiedWatersLicenseNumber = nil
          }
        }
      }
    }
  }

  @ViewBuilder private func optionalSection() -> some View {
    Section(header: Text("Optional").foregroundColor(.white)) {
      // Notes
      VStack(alignment: .leading, spacing: 6) {
        Text("Field Notes").font(.subheadline).foregroundColor(.secondary)
        ZStack(alignment: .leading) {
          if vm.notes.isEmpty {
            Text("For example… Scars present from previous catch")
              .italic().foregroundColor(.gray).padding(.vertical, 6)
          }
          TextEditor(text: $vm.notes).frame(minHeight: 80)
        }
      }

      // Photo preview + actions
      if let photo = vm.photo {
        VStack(alignment: .leading, spacing: 8) {
          Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .cornerRadius(8)

          HStack {
            Button {
              guard !isPresentingPicker, activePicker == nil else { return }
              activePicker = .library
            } label: {
              Label("Replace Photo", systemImage: "photo.on.rectangle")
            }

            Spacer()

            Button {
              vm.photo = nil
              vm.photoPath = nil
            } label: {
              Label("Remove", systemImage: "trash")
            }
          }
        }
      } else {
        HStack(spacing: 12) {
          Button {
            guard !isPresentingPicker, activePicker == nil else { return }
            activePicker = .library
          } label: {
            Label("Photo Library", systemImage: "photo.on.rectangle")
          }

          Button {
            guard !isPresentingPicker, activePicker == nil else { return }
            activePicker = .camera
          } label: {
            Label("Camera", systemImage: "camera")
          }
        }
      }
    }
  }

  @ViewBuilder private func systemSection() -> some View {
    Section(header: Text("System Details").foregroundColor(.white)) {
      HStack { Text("Community"); Spacer(); Text(AppEnvironment.shared.communityName).foregroundColor(.secondary) }

      HStack(spacing: 8) {
        Image(systemName: "location.fill")
        if let l = loc.lastLocation {
          Text(String(format: "%.5f, %.5f", l.coordinate.latitude, l.coordinate.longitude))
            .font(.footnote).foregroundColor(.secondary)
        } else {
          Text("Acquiring GPS…").font(.footnote).foregroundColor(.secondary)
        }
      }
      HStack(spacing: 8) {
        Image(systemName: "clock")
        Text(Date(), style: .date)
        Text(Date(), style: .time)
      }.foregroundColor(.secondary)
    }
  }

  @ViewBuilder private func saveSection() -> some View {
    Section {
      Button {
        vm.save(context: context, trip: selectedTrip) { success in
          if success {
            dismiss() // ✅ Always return to LandingView when save succeeds
          } else {
            // Optionally keep the form open and let the toast show the error
          }
        }
      } label: {
        HStack {
          Spacer()
          if vm.isSaving { ProgressView() } else { Text("Save Report").fontWeight(.semibold) }
          Spacer()
        }
      }
      .disabled(!formIsValid)

      // Optional hints
      if !formIsValid {
        VStack(alignment: .leading, spacing: 4) {
          if selectedTripID == nil { Text("• Select a trip").foregroundColor(.secondary) }
          if selectedClientID == nil { Text("• Select an angler").foregroundColor(.secondary) }
          if selectedClientID != nil,
             selectedClientAnglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("• Angler ID is required").foregroundColor(.secondary)
          }
          if vm.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("• Choose a species").foregroundColor(.secondary)
          }
          if vm.lengthInches <= 0 { Text("• Enter a positive length").foregroundColor(.secondary) }
          if vm.origin == "Hatchery", vm.tagId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("• Tag ID required for Hatchery origin").foregroundColor(.secondary)
          }
        }
        .font(.footnote)
      }
    }
  }

  // MARK: - Derived selections & validation

  private var selectedTrip: Trip? {
    guard let id = selectedTripID else { return nil }
    return trips.first(where: { $0.objectID == id })
  }

  private var formIsValid: Bool {
    guard selectedTrip != nil, selectedClientID != nil, !vm.isSaving else { return false }
    let anglerOK = !selectedClientAnglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let speciesOK = !vm.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let lengthOK = vm.lengthInches > 0
    let tagOK = (vm.origin != "Hatchery") || !vm.tagId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return anglerOK && speciesOK && lengthOK && tagOK
  }

  // MARK: - Helpers

  private func tripDisplay(_ t: Trip) -> String {
    let start = t.startDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
    let end = t.endDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
    let guide = t.guideName ?? "Guide"
    return "\(guide) — \(start)–\(end)"
  }

  private func reloadClients() {
    clientOptions.removeAll()
    guard let trip = selectedTrip else { return }
    let req: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    req.predicate = NSPredicate(format: "trip == %@", trip)
    req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
    let results = (try? context.fetch(req)) ?? []
    clientOptions = results
      .map { ClientOption(id: $0.objectID, name: ($0.name ?? "").trimmedOrUnnamed) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func reloadLicenses() {
    licenseOptions.removeAll()
    guard let cid = selectedClientID,
          let client = try? context.existingObject(with: cid) as? TripClient else { return }

    let set = (client.classifiedLicenses as? Set<ClassifiedWaterLicense>) ?? []
    licenseOptions = set
      .map { LicenseOption(id: $0.objectID, display: licenseDisplay($0)) }
      .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
  }

  private func licenseDisplay(_ l: ClassifiedWaterLicense) -> String {
    let num = l.licNumber ?? "—"
    let water = l.water ?? "—"
    let from = l.validFrom.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
    let to = l.validTo.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
    return "\(water) • \(num) (\(from)–\(to))"
  }
}

// MARK: - Full-screen UIImagePickerController wrapper (single presenter uses this)

private struct ImagePickerFullScreen: UIViewControllerRepresentable {
  let sourceType: UIImagePickerController.SourceType
  let onPickedPhoto: (PickedPhoto) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onPickedPhoto: onPickedPhoto, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let p = UIImagePickerController()
    p.sourceType = sourceType
    p.delegate = context.coordinator
    p.allowsEditing = false
    return p
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let onPickedPhoto: (PickedPhoto) -> Void
    let onCancel: () -> Void

    init(onPickedPhoto: @escaping (PickedPhoto) -> Void, onCancel: @escaping () -> Void) {
      self.onPickedPhoto = onPickedPhoto
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      guard let img = info[.originalImage] as? UIImage else {
        onCancel()
        return
      }

      var exifDate: Date?
      var exifLocation: CLLocation?

      if let asset = info[.phAsset] as? PHAsset {
        exifDate = asset.creationDate
        exifLocation = asset.location
      }

      let picked = PickedPhoto(
        image: img,
        exifDate: exifDate,
        exifLocation: exifLocation
      )

      onPickedPhoto(picked)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
    }
  }
}

// MARK: - Small structs & helpers

private struct ClientOption: Identifiable, Hashable {
  let id: NSManagedObjectID
  let name: String
}

private struct LicenseOption: Identifiable, Hashable {
  let id: NSManagedObjectID
  let display: String
}

private extension Array { var only: Element? { count == 1 ? first : nil } }
private extension String {
  var trimmedOrUnnamed: String {
    let t = trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "(Unnamed)" : t
  }
}

// Safe probe to avoid KVC crashes if TripClient lacks an attribute
private func safeAnglerNumber(from client: TripClient) -> String? {
  let attrs = client.entity.attributesByName
  // "licenseNumber" is used in your model; try it first
  for key in ["licenseNumber", "anglerNumber", "bcAnglerNumber", "anglerID", "clientNumber"] {
    if attrs[key] != nil,
       let v = client.value(forKey: key) as? String,
       !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
  return nil
}
private struct HideListBackgroundIfAvailable: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}
