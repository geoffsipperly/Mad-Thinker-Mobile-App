// Bend Fly Shop

import Combine
import CoreData
import CoreLocation
import SwiftUI
import UIKit

struct ReportChatView: View {
  @Environment(\.managedObjectContext) private var context
  @Environment(\.dismiss) private var dismiss

  @StateObject private var vm = ReportFormViewModel()
  @StateObject private var loc = LocationManager()

  @StateObject private var chatVM = CatchChatViewModel()

  // Trips (in-progress)
  @State private var trips: [Trip] = []

  @State private var selectedTripID: NSManagedObjectID?
  @State private var selectedClientID: NSManagedObjectID?
  @State private var clientOptions: [ClientOption] = []

  @State private var selectedLicenseID: NSManagedObjectID?
  @State private var licenseOptions: [LicenseOption] = []
  @State private var selectedLicenseNumber: String?

  // Solo mode
  @State private var isSoloMode = false
  @State private var showSoloAnglerPrompt = false
  @State private var soloAnglerNumberInput = ""
  @State private var soloSaving = false
  @State private var soloErrorMessage: String?

  // Navigation to full-screen chat
  @State private var showChatFullScreen = false

  private let labelFont: Font = .subheadline
  private let labelColor: Color = .blue
  private let valueFontSelected: Font = .subheadline
  private let valueFontPlaceholder: Font = .footnote
  private let valueColor: Color = .white

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        header
        Spacer().frame(height: 40)
        captureButton
        Spacer()
      }
    }
    .navigationTitle("Record a catch")
    .navigationBarTitleDisplayMode(.inline)
    .preferredColorScheme(.dark)
    .toolbar {
      // Cancel on "Record a Catch" view
        ToolbarItem(placement: .topBarTrailing) {
        Button("Cancel") {
          cancelToLanding()
        }
        }
    }
    .onAppear(perform: handleOnAppear)
    .onDisappear(perform: handleOnDisappear)
    .onReceive(loc.$lastLocation) { location in
      vm.currentLocation = location
      chatVM.updateLocation(location)
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
      // Any context saved -> reload trips from Core Data
      loadTrips()
    }

    .onChange(of: selectedTripID) { _ in
      handleTripChanged()
      chatVM.updateTripContext(trip: currentTripText())

    }
    .onChange(of: selectedClientID) { _ in
      handleClientChanged()
      chatVM.updateAnglerContext(angler: vm.clientName)
    }
    // Watch for saveRequested flag from the chat VM
    .onChange(of: chatVM.saveRequested) { newValue in
      if newValue {
        savePicMemoCatchIfPossible()
      }
    }
    .fullScreenCover(isPresented: $showChatFullScreen) {
      CatchChatFullScreenView(
        viewModel: chatVM,
        onCatchSaved: {
          // On save, go back to landing (original behavior)
          dismiss()
        },
        onCancel: {
          // User cancelled from "Record Catch Details":
          // 1) Clear any in-memory form state
          resetFlowState()
          // 2) Close the full-screen cover
          showChatFullScreen = false
          // 3) Dismiss ReportChatView back to landing
          dismiss()
        }
      )
      .environment(\.managedObjectContext, context)
    }
  }

  // MARK: - Lifecycle

  private func handleOnAppear() {
    loc.request()
    loc.start()

    // Reload trips from Core Data, then pick a default if needed
    loadTrips()

    // Seed chat VM with the logged-in guide (not the trip's guide)
    let loggedInGuide = (AuthService.shared.currentFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    vm.guideName = loggedInGuide
    chatVM.updateGuideContext(guide: loggedInGuide)
    chatVM.updateAnglerContext(angler: currentClientText())
    chatVM.updateTripContext(trip: currentTripText())
  }

  private func handleOnDisappear() {
    loc.stop()
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 12) {
      soloToggleCard
      if !isSoloMode {
        tripCard
        clientCard
        licenceCard
      }
    }
    .padding(.top, 6)
    .padding(.bottom, 4)
  }

  private var soloToggleCard: some View {
    Button(action: {
      withAnimation(.easeInOut(duration: 0.25)) {
        isSoloMode.toggle()
      }
      if isSoloMode {
        handleSoloActivated()
      } else {
        handleSoloDeactivated()
      }
    }) {
      HStack {
        Image(systemName: isSoloMode ? "person.fill.checkmark" : "person.fill")
          .font(.subheadline)
          .foregroundColor(isSoloMode ? .green : .white.opacity(0.7))
        Text(isSoloMode ? "Fishing Solo" : "Fishing Solo?")
          .font(.subheadline)
          .foregroundColor(isSoloMode ? .green : .white)
        Spacer()
        if isSoloMode {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isSoloMode ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
      .cornerRadius(16)
      .padding(.horizontal)
    }
    .alert("Enter Your Angler License #", isPresented: $showSoloAnglerPrompt) {
      TextField("License number", text: $soloAnglerNumberInput)
        .keyboardType(.numberPad)
      Button("Save") {
        Task { await saveSoloAnglerNumber() }
      }
      .disabled(soloAnglerNumberInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Cancel", role: .cancel) {
        // Revert solo mode since they cancelled
        withAnimation { isSoloMode = false }
      }
    } message: {
      Text("To record solo catches, we need your angler license number. This is saved to your profile and can be updated anytime.")
    }
  }

  private var tripCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Select a trip")
        .font(labelFont)
        .foregroundColor(labelColor)

      Menu {
        ForEach(trips, id: \.objectID) { trip in
          Button(tripDisplay(trip)) {
            selectedTripID = trip.objectID
          }
        }
      } label: {
        HStack {
          Text(currentTripText())
            .font(currentTripText() == "Select" ? valueFontPlaceholder : valueFontSelected)
            .foregroundColor(valueColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
          Spacer(minLength: 4)
          Image(systemName: "chevron.down")
            .font(.footnote)
            .foregroundColor(.white.opacity(0.7))
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.08))
    .cornerRadius(16)
    .padding(.horizontal)
  }

  private var clientCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Angler name")
        .font(labelFont)
        .foregroundColor(labelColor)

      Group {
        if clientOptions.isEmpty {
          Text("No clients on this trip")
            .font(valueFontPlaceholder)
            .foregroundColor(valueColor.opacity(0.6))
        } else {
          Menu {
            ForEach(clientOptions) { opt in
              Button(opt.name) { selectedClientID = opt.id }
            }
          } label: {
            HStack {
              Text(currentClientText())
                .font(currentClientText() == "Select" ? valueFontPlaceholder : valueFontSelected)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
              Spacer(minLength: 4)
              Image(systemName: "chevron.down")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            }
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.08))
    .cornerRadius(16)
    .padding(.horizontal)
  }

  private var licenceCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Select a classified waters license")
        .font(labelFont)
        .foregroundColor(labelColor)

      Group {
        if selectedClientID == nil {
          Text("-")
            .font(valueFontPlaceholder)
            .foregroundColor(valueColor.opacity(0.6))
        } else if licenseOptions.isEmpty {
          Text("No licences")
            .font(valueFontPlaceholder)
            .foregroundColor(valueColor.opacity(0.6))
        } else {
          Menu {
            Button("No Valid Licence") {
              selectedLicenseID = nil
              updateSelectedLicence()
            }
            Divider()
            ForEach(licenseOptions) { opt in
              Button(opt.display) {
                selectedLicenseID = opt.id
                updateSelectedLicence()
              }
            }
          } label: {
            let isPlaceholder = (selectedLicenseID == nil)
            HStack {
              Text(currentLicenceText())
                .font(isPlaceholder ? valueFontPlaceholder : valueFontSelected)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
              Spacer(minLength: 4)
              Image(systemName: "chevron.down")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            }
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.08))
    .cornerRadius(16)
    .padding(.horizontal)
  }

  // MARK: - Capture button (new flow entry point)

  private var captureButton: some View {
    Button(action: startCaptureFlow) {
      HStack {
        Spacer()
        Text("Next")
          .font(.headline)
          .foregroundColor(.white)
          .padding(.vertical, 12)
        Spacer()
      }
      .background(Color.blue)
      .cornerRadius(14)
      .padding(.horizontal)
    }
    .padding(.top, 8)
    .disabled(!isCaptureEnabled)
    .opacity(isCaptureEnabled ? 1.0 : 0.4)
  }

  private var isCaptureEnabled: Bool {
    if isSoloMode {
      let anglerNum = (AuthService.shared.currentAnglerNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return !anglerNum.isEmpty
    }
    return selectedClientID != nil &&
      !vm.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func startCaptureFlow() {
    // Prepare any context the chat VM should know before starting
    chatVM.updateGuideContext(guide: vm.guideName)
    chatVM.updateAnglerContext(angler: vm.clientName)
    chatVM.updateTripContext(trip: currentTripText())

    // Start the conversation if needed
    chatVM.startConversationIfNeeded()

    showChatFullScreen = true
  }

  // MARK: - Cancel helpers

  /// Cancel from "Record a Catch" – clear state and go back to landing.
  private func cancelToLanding() {
    resetFlowState()
    dismiss()
  }

  /// Clears in-memory state so cancelling doesn't leave partial data hanging around.
  private func resetFlowState() {
    // Clear view-model fields
    vm.guideName = ""
    vm.clientName = ""
    vm.anglerNumber = ""
    vm.classifiedWatersLicenseNumber = nil

    // Clear solo mode
    isSoloMode = false
    soloAnglerNumberInput = ""
    soloErrorMessage = nil

    // Clear selections and options
    selectedTripID = nil
    selectedClientID = nil
    selectedLicenseID = nil
    selectedLicenseNumber = nil
    clientOptions = []
    licenseOptions = []

    // Note: chatVM state will be dropped when this view is dismissed.
  }

  // MARK: - Solo mode helpers

  private func handleSoloActivated() {
    let existingNumber = (AuthService.shared.currentAnglerNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if existingNumber.isEmpty {
      // First time — prompt for angler number
      soloAnglerNumberInput = ""
      showSoloAnglerPrompt = true
    } else {
      // Already have a number — pre-populate and activate
      configureSoloState(anglerNumber: existingNumber)
    }
  }

  private func handleSoloDeactivated() {
    // Restore normal mode — clear solo overrides
    vm.anglerNumber = ""
    vm.clientName = ""
    vm.classifiedWatersLicenseNumber = nil
    // Re-trigger normal trip/client selection
    if let tid = selectedTripID {
      selectedTripID = tid // re-fire onChange
    }
  }

  private func saveSoloAnglerNumber() async {
    let trimmed = soloAnglerNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      try await AuthService.shared.updateAnglerNumber(trimmed)
      await MainActor.run {
        configureSoloState(anglerNumber: trimmed)
      }
    } catch {
      await MainActor.run {
        soloErrorMessage = error.localizedDescription
        withAnimation { isSoloMode = false }
      }
    }
  }

  private func configureSoloState(anglerNumber: String) {
    let guideName = (AuthService.shared.currentFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    vm.anglerNumber = anglerNumber
    vm.clientName = guideName
    vm.classifiedWatersLicenseNumber = nil
    vm.guideName = guideName
    chatVM.updateAnglerContext(angler: guideName)
    chatVM.updateGuideContext(guide: guideName)
  }

  /// Finds or creates a same-day solo trip in Core Data.
  /// Returns the Trip to use for the catch report.
  private func findOrCreateSoloTrip() -> Trip? {
    let today = Calendar.current.startOfDay(for: Date())
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

    // Look for an existing solo trip created today
    let request: NSFetchRequest<Trip> = Trip.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      NSPredicate(format: "name BEGINSWITH %@", "Solo"),
      NSPredicate(format: "startDate >= %@ AND startDate < %@", today as NSDate, tomorrow as NSDate)
    ])
    request.fetchLimit = 1

    if let existing = (try? context.fetch(request))?.first {
      return existing
    }

    // Create a new solo trip
    let guideName = (AuthService.shared.currentFirstName ?? "Guide").trimmingCharacters(in: .whitespacesAndNewlines)
    let guideLastName = (AuthService.shared.currentLastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let anglerNumber = (AuthService.shared.currentAnglerNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let df = DateFormatter()
    df.dateFormat = "MMM d"
    let tripName = "Solo – \(df.string(from: Date()))"

    let trip = Trip(context: context)
    trip.tripId = UUID()
    trip.guideName = guideName
    trip.name = tripName
    trip.startDate = today
    trip.endDate = today
    trip.createdAt = Date()

    // Create a TripClient for the guide themselves
    let client = TripClient(context: context)
    client.name = guideName
    client.licenseNumber = anglerNumber
    client.trip = trip

    do {
      try context.save()
      AppLogging.log("[Solo] Created solo trip: \(tripName) id=\(trip.tripId?.uuidString ?? "?")", level: .info, category: .trip)

      // Upload the solo trip to the server (fire-and-forget)
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime]
      let upsert = TripAPI.UpsertTripRequest(
        tripId: trip.tripId?.uuidString ?? UUID().uuidString,
        tripName: tripName,
        startDate: iso.string(from: today),
        endDate: iso.string(from: today),
        guideName: guideName,
        clientName: nil,
        community: AppEnvironment.shared.communityName,
        lodge: nil,
        anglers: [
          .init(
            anglerNumber: anglerNumber,
            firstName: guideName,
            lastName: guideLastName.isEmpty ? nil : guideLastName,
            dateOfBirth: nil,
            residency: nil,
            sex: nil,
            mailingAddress: nil,
            telephoneNumber: nil,
            classifiedWatersLicenses: nil
          )
        ]
      )
      Task {
        await AuthStore.shared.refreshFromSupabase()
        if let jwt = AuthStore.shared.jwt {
          _ = try? await TripAPI.upsertTrip(upsert, jwt: jwt)
        }
      }

      return trip
    } catch {
      AppLogging.log("[Solo] Failed to create solo trip: \(error)", level: .error, category: .trip)
      return nil
    }
  }

  // MARK: - Trips loading

  private func loadTrips() {
    let now = Date()
    let startOfToday = Calendar.current.startOfDay(for: now)
    // Use start-of-yesterday so same-day trips remain visible the next day
    // instead of vanishing once the calendar date rolls over.
    let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)!

    let startedPredicate = NSPredicate(format: "startDate <= %@", now as NSDate)
    let openOrRecentlyEndedPredicate = NSPredicate(
      format: "endDate == nil OR endDate >= %@", startOfYesterday as NSDate
    )
    let combined = NSCompoundPredicate(
      andPredicateWithSubpredicates: [startedPredicate, openOrRecentlyEndedPredicate]
    )

    let request: NSFetchRequest<Trip> = Trip.fetchRequest()
    request.predicate = combined
    request.sortDescriptors = [NSSortDescriptor(keyPath: \Trip.createdAt, ascending: false)]

    do {
      trips = try context.fetch(request)
      // Debug logging of fetched trips (count and concise details)
      let summaries: [String] = trips.map { t in
        let id = t.objectID.uriRepresentation().absoluteString
        let name = (t.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let start = t.startDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
        let end = t.endDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—"
        let guide = (t.guideName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Guide"
        let label = name ?? "\(guide) — \(start)–\(end)"
        return "{id=\(id), label=\(label)}"
      }
      AppLogging.log({
        "loadTrips fetched \(trips.count) trip(s): \n\(summaries.joined(separator: "\n"))"
      }, level: .debug, category: .trip)
      setDefaultTripIfNeeded()
    } catch {
      print("❌ Failed to fetch trips: \(error)")
    }
  }

  // MARK: - Default trip helper

  private func setDefaultTripIfNeeded() {
    guard !trips.isEmpty else {
      selectedTripID = nil
      return
    }

    // Only set a default if user hasn't picked a trip yet
    if selectedTripID == nil {
      selectedTripID = trips.first?.objectID
    }
  }

  // MARK: - Current value helpers

  private func currentTripText() -> String {
    guard let id = selectedTripID,
          let t = trips.first(where: { $0.objectID == id })
    else {
      return "No trips created"
    }
    return tripDisplay(t)
  }

  private func currentClientText() -> String {
    guard let id = selectedClientID,
          let o = clientOptions.first(where: { $0.id == id })
    else {
      return "Select"
    }
    return o.name
  }

  private func currentLicenceText() -> String {
    guard let id = selectedLicenseID,
          let o = licenseOptions.first(where: { $0.id == id })
    else {
      return "No Valid Licence"
    }
    return o.display
  }

  // MARK: - Data helpers

  private var selectedTrip: Trip? {
    guard let id = selectedTripID else { return nil }
    return trips.first(where: { $0.objectID == id })
  }

  private func tripDisplay(_ t: Trip) -> String {
    if let name = t.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }

    let start = t.startDate.map {
      DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
    } ?? "—"

    let end = t.endDate.map {
      DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
    } ?? "—"

    let guide = t.guideName ?? "Guide"
    return "\(guide) — \(start)–\(end)"
  }

  private func handleTripChanged() {
    // Always use the logged-in guide, not the trip's guide
    let loggedInGuide = (AuthService.shared.currentFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    vm.guideName = loggedInGuide
    chatVM.updateGuideContext(guide: loggedInGuide)

    reloadClients()
    selectedClientID = clientOptions.count == 1 ? clientOptions.first?.id : nil
    vm.clientName = ""
    licenseOptions = []
    selectedLicenseID = nil
    selectedLicenseNumber = nil
  }

  private func handleClientChanged() {
    vm.clientName = clientOptions.first(where: { $0.id == selectedClientID })?.name ?? ""
    chatVM.updateAnglerContext(angler: vm.clientName)

    if let cid = selectedClientID,
       let clientObj = try? context.existingObject(with: cid) as? TripClient,
       let auto = safeAnglerNumber(from: clientObj) {
      vm.anglerNumber = auto
    } else {
      vm.anglerNumber = ""
    }

    reloadLicenses()
    selectedLicenseID = nil
    selectedLicenseNumber = nil
    vm.classifiedWatersLicenseNumber = nil
  }

  private func updateSelectedLicence() {
    if let licID = selectedLicenseID,
       let lic = try? context.existingObject(with: licID) as? ClassifiedWaterLicense {
      let trimmed = lic.licNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
      selectedLicenseNumber = trimmed
      vm.classifiedWatersLicenseNumber = trimmed
    } else {
      selectedLicenseNumber = nil
      vm.classifiedWatersLicenseNumber = nil
    }
  }

  private func reloadClients() {
    clientOptions.removeAll()
    guard let trip = selectedTrip else { return }

    let request: NSFetchRequest<TripClient> = TripClient.fetchRequest()
    request.predicate = NSPredicate(format: "trip == %@", trip)
    request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

    let results = (try? context.fetch(request)) ?? []

    let mapped = results.map { client in
      ClientOption(
        id: client.objectID,
        name: (client.name ?? "").trimmedOrUnnamed
      )
    }

    clientOptions = mapped.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func reloadLicenses() {
    licenseOptions.removeAll()

    guard let cid = selectedClientID,
          let client = try? context.existingObject(with: cid) as? TripClient
    else {
      return
    }

    let set = (client.classifiedLicenses as? Set<ClassifiedWaterLicense>) ?? []

    let mapped = set.map { license in
      LicenseOption(
        id: license.objectID,
        display: licenseDisplay(license)
      )
    }

    licenseOptions = mapped.sorted {
      $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
    }
  }

  private func licenseDisplay(_ l: ClassifiedWaterLicense) -> String {
    let num = l.licNumber ?? "—"
    let water = l.water ?? "—"

    let from = l.validFrom.map {
      DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
    } ?? "—"

    let to = l.validTo.map {
      DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
    } ?? "—"

    return "\(water) • \(num) (\(from)–\(to))"
  }

  // MARK: - PicMemo Save (now using createFromChat)

  private func savePicMemoCatchIfPossible() {
    guard let snapshot = chatVM.makePicMemoSnapshot() else {
      return
    }

    // Resolve trip — solo mode creates/reuses a same-day trip automatically
    let trip: Trip? = isSoloMode ? findOrCreateSoloTrip() : selectedTrip

    let anglerNumber = vm.anglerNumber
    let cwlNumber = vm.classifiedWatersLicenseNumber
    let tripIdString = trip?.tripId?.uuidString

    let communityName = isSoloMode ? AppEnvironment.shared.communityName : trip?.lodge?.community?.name
    let lodgeName = isSoloMode ? nil : trip?.lodge?.name
    let loggedInGuide = (AuthService.shared.currentFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let guideName = loggedInGuide.isEmpty ? snapshot.guideName : loggedInGuide

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let deviceDescription = "\(UIDevice.current.model) \(UIDevice.current.systemVersion)"

    // Derive a human-readable trip name for v2 API (match PicMemo display)
    let rawTripName = trip?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let tripNameValue: String? = {
      if let n = rawTripName, !n.isEmpty { return n }
      if isSoloMode { return nil } // solo trips already have a name set above
      let label = currentTripText()
      if label == "No trips created" { return nil }
      return label
    }()

    CatchReportPicMemoStore.shared.createFromChat(
      anglerNumber: anglerNumber.isEmpty ? "Unknown" : anglerNumber,
      species: snapshot.species,
      sex: snapshot.sex,
      origin: "Wild",
      lengthInches: snapshot.lengthInches ?? 0,
      lifecycleStage: snapshot.lifecycleStage,
      river: snapshot.riverName,
      classifiedWatersLicenseNumber: cwlNumber,
      lat: snapshot.latitude,
      lon: snapshot.longitude,
      photoFilename: snapshot.photoFilename,
      voiceNoteId: snapshot.voiceNoteId,
      tripId: tripIdString,
      tripName: tripNameValue,
      tripStartDate: trip?.startDate,
      tripEndDate: trip?.endDate,
      guideName: guideName,
      community: communityName,
      lodge: lodgeName,
      initialRiverName: snapshot.initialRiverName,
      initialSpecies: snapshot.initialSpecies,
      initialLifecycleStage: snapshot.initialLifecycleStage,
      initialSex: snapshot.initialSex,
      initialLengthInches: snapshot.initialLengthInches,
      mlFeatureVector: snapshot.mlFeatureVector,
      lengthSource: snapshot.lengthSource,
      modelVersion: snapshot.modelVersion,
      appVersion: appVersion,
      deviceDescription: deviceDescription,
      platform: "iOS",
      catchDate: chatVM.photoTimestamp
    )
  }
}

// MARK: - Full-screen chat wrapper

private struct CatchChatFullScreenView: View {
  @Environment(\.dismiss) private var dismissCover

  @ObservedObject var viewModel: CatchChatViewModel
  let onCatchSaved: () -> Void
  let onCancel: () -> Void

  @State private var showCatchSavedAlert = false

  var body: some View {
    NavigationView {
      CatchChatView(viewModel: viewModel)
        .navigationTitle("Record Catch Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          // Cancel on "Record Catch Details"
            ToolbarItem(placement: .topBarTrailing) {
            Button("Cancel") {
              onCancel()
            }
            }
        }
    }
    .background(Color.black.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .onChange(of: viewModel.saveRequested) { newValue in
      if newValue {
        showCatchSavedAlert = true
      }
    }
    .alert("Catch Saved", isPresented: $showCatchSavedAlert) {
      Button(action: {
        // clear the flag so we don't retrigger
        viewModel.saveRequested = false

        // 1) dismiss the full-screen chat
        dismissCover()

        // 2) then dismiss ReportChatView back to LandingView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          onCatchSaved()
        }
      }) {
        Text("OK").foregroundColor(.white)
      }
    } message: {
      Text("Your catch has been saved locally.")
    }
    .tint(.blue)
  }
}

// MARK: - Support types & utilities

private struct ClientOption: Identifiable, Hashable {
  let id: NSManagedObjectID
  let name: String
}

private struct LicenseOption: Identifiable, Hashable {
  let id: NSManagedObjectID
  let display: String
}

private extension String {
  var trimmedOrUnnamed: String {
    let t = trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "(Unnamed)" : t
  }
}

private func safeAnglerNumber(from client: TripClient) -> String? {
  let attrs = client.entity.attributesByName

  let keys = [
    "licenseNumber",
    "anglerNumber",
    "bcAnglerNumber",
    "anglerID",
    "clientNumber"
  ]

  for key in keys {
    if attrs[key] != nil,
       let value = client.value(forKey: key) as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }
  }
  return nil
}
