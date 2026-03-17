// TripDetailView.swift
// Bend Fly Shop

import CoreData
import SwiftUI
import UIKit

// Local TripStatus used for display (keeps this file self-contained)
private enum TripStatus: String {
  case notStarted = "Not started"
  case inProgress = "In progress"
  case completed = "Completed"
}

struct TripDetailView: View {
  @Environment(\.managedObjectContext) private var context
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var trip: Trip // observe so UI updates after Core Data saves

  // Programmatic navigation to Edit screen (more stable than sheet)
  @State private var goToEdit = false

  // Freeze "now" while screen is visible so status doesn't flicker
  @State private var nowSnapshot: Date = .init()

  // Pending in-memory drafts mirrored from TripEditForm for preview in detail
  @State private var pendingAnglers: [TripEditForm.NewAnglerDraft] = []
  @State private var hasChanges: Bool = false

  // MARK: - Status

  /// Matches list/fetch logic: In Progress = (start <= now) AND (end == nil OR end >= startOfToday)
  private func computeStatus(start: Date?, end: Date?, now: Date) -> TripStatus {
    let startOfToday = Calendar.current.startOfDay(for: now)
    guard let s = start else { return .notStarted } // defensive default
    if s > now { return .notStarted }
    let inProgress = (s <= now) && (end == nil || (end ?? now) >= startOfToday)
    return inProgress ? .inProgress : .completed
  }

  private var status: TripStatus {
    computeStatus(start: trip.startDate, end: trip.endDate, now: nowSnapshot)
  }

  private var canEdit: Bool {
    switch status {
    case .notStarted, .inProgress: true
    case .completed: false
    }
  }

  // MARK: - To-many helpers (NSSet -> [Entity])

  private var clientArray: [TripClient] {
    let set = trip.clients as? Set<TripClient> ?? []
    return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
  }

  // Helper: get Classified Water Licences for a client, sorted
  private func licenses(for client: TripClient) -> [ClassifiedWaterLicense] {
    // If your inverse is named differently, change `classifiedLicenses` below.
    let set = client.classifiedLicenses as? Set<ClassifiedWaterLicense> ?? []
    return set.sorted { a, b in
      let aFrom = a.validFrom ?? .distantPast
      let bFrom = b.validFrom ?? .distantPast
      if aFrom != bFrom { return aFrom < bFrom }
      return (a.water ?? "") < (b.water ?? "")
    }
  }

  private func displayName(for client: TripClient) -> String {
    // If you later persist first/last separately, prefer those here.
    let name = (client.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "(Unnamed)" : name
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      List {
        // Trip summary
        Section {
          HStack {
            Text("Lodge")
            Spacer()
            Text(trip.lodge?.name ?? "-")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Trip Name")
            Spacer()
            Text(trip.name ?? "-")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Dates")
            Spacer()
            Text("\(dayString(trip.startDate)) – \(dayString(trip.endDate))")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Status")
            Spacer()
            StatusPill(status: status) // consistent colors with list
          }
        }
        .listRowBackground(Color.black)

        // Anglers list with Classified Waters
        Section(header: Text("Anglers")) {
          if clientArray.isEmpty && pendingAnglers.isEmpty {
            Text("No anglers listed.")
              .foregroundColor(.secondary)
          } else {
            // First: show existing Core Data anglers
            ForEach(clientArray, id: \.objectID) { client in
              anglerClientRow(client: client, licenses: licenses(for: client)) {
                // remove action
                removeAngler(client)
              }
            }

            // Next: show pending angler drafts (these are previews that will be applied on Save)
            ForEach(Array(pendingAnglers.enumerated()), id: \.element.id) { idx, draft in
              VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                  VStack(alignment: .leading) {
                    Text(draft.name.isEmpty ? "(Unnamed)" : draft.name)
                      .font(.body)
                    if !draft.license.isEmpty {
                      Text("License: \(draft.license)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                  }
                  Spacer()
                  Button(role: .destructive) {
                    withAnimation {
                      pendingAnglers.remove(at: idx)
                      hasChanges = true
                      trip.localUpdatedAt = Date()
                    }
                  } label: {
                    Image(systemName: "trash")
                  }
                  .buttonStyle(.plain)
                }

                // Classified Waters for draft (if any)
                if draft.licences.isEmpty {
                  Text("No Classified Waters licences.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                  VStack(alignment: .leading, spacing: 6) {
                    Text("Classified Waters")
                      .font(.caption).fontWeight(.semibold)
                      .foregroundColor(.secondary)

                    ForEach(draft.licences, id: \.id) { r in
                      VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.water.isEmpty ? "—" : r.water) • \(r.licNumber)")
                          .font(.callout)
                        HStack(spacing: 8) {
                          if let from = r.validFrom {
                            Text("From: \(from.formatted(date: .abbreviated, time: .omitted))")
                              .font(.caption)
                          }
                          if let to = r.validTo {
                            Text("To: \(to.formatted(date: .abbreviated, time: .omitted))")
                              .font(.caption)
                          }
                        }
                      }
                      .padding(.vertical, 2)
                    }
                  }
                  .padding(.top, 2)
                }
              }
              .padding(.vertical, 6)
              .listRowBackground(Color.black)
            }
          }
        }
        .listRowBackground(Color.black)
      }
      .listStyle(.plain)
      .background(Color.black)
      .modifier(HideListBackgroundIfAvailable())
      .environment(\.colorScheme, .dark)
      .navigationTitle("Trip details")
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            dismiss()
          } label: {
            HStack {
              Image(systemName: "chevron.backward")
              Text("Back")
            }
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            if canEdit { goToEdit = true }
          } label: {
            Text("Edit")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14)
              .padding(.vertical, 6)
              .background(Color.blue)
              .clipShape(Capsule())
              .foregroundColor(.white)
          }
          .buttonStyle(PlainButtonStyle())
          .disabled(!canEdit)
          .opacity(canEdit ? 1.0 : 0.6)
        }
      }
      // Apply toolbarBackground only on iOS16+, safely.
      .applyNavigationBarToolbarBackground()
      .navigationDestination(isPresented: $goToEdit) {
        TripEditForm(trip: trip)
          .id(trip.objectID) // extra stability if Core Data refreshes
      }
      .onAppear {
        nowSnapshot = Date() // freeze "now" while this screen is visible
        loadPendingIfNeeded()
      }
      .onDisappear {
        NotificationCenter.default.post(name: .tripDidChange, object: nil)
      }
    }
  }

  // MARK: - Small helpers & subviews

  private func dayString(_ date: Date?) -> String {
    guard let d = date else { return "-" }
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  /// Row for a persisted TripClient
  @ViewBuilder
  private func anglerClientRow(client: TripClient, licenses: [ClassifiedWaterLicense], removeAction: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(displayName(for: client))
        .font(.body)
      if let lic = client.licenseNumber, !lic.isEmpty {
        Text("License: \(lic)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if licenses.isEmpty {
        Text("No Classified Waters licences.")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text("Classified Waters")
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)

          ForEach(licenses, id: \.objectID) { r in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(r.water ?? "—") • \(r.licNumber ?? "—")")
                .font(.callout)
              HStack(spacing: 8) {
                if let from = r.validFrom {
                  Text("From: \(from.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                }
                if let to = r.validTo {
                  Text("To: \(to.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                }
              }
            }
            .padding(.vertical, 2)
          }
        }
        .padding(.top, 2)
      }

      HStack {
        Spacer()
        Button(role: .destructive) {
          removeAction()
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 6)
  }

  // MARK: - Additional helpers required by TripDetailView (for pendingAnglers etc)

  private func loadPendingIfNeeded() {
    // No-op currently; kept for extension if you persist previews across navigation
  }

  private func removeAngler(_ client: TripClient) {
    context.delete(client)
    do {
      try context.save()
      trip.localUpdatedAt = Date()
      NotificationCenter.default.post(name: .tripDidChange, object: nil)
    } catch {
      print("[TripDetailView] Failed to remove angler:", error)
    }
  }
}

// MARK: - Status pill with consistent colors (matches list StatusBadge)

private struct StatusPill: View {
  let status: TripStatus

  var body: some View {
    Text(status.rawValue) // assumes global TripStatus is String-backed
      .font(.caption2)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(background)
      .foregroundColor(foreground)
      .clipShape(Capsule())
      .accessibilityLabel("Trip status \(status.rawValue)")
  }

  private var background: Color {
    switch status {
    case .notStarted: Color.yellow.opacity(0.18) // light yellow
    case .inProgress: Color.green.opacity(0.18) // green
    case .completed: Color.gray.opacity(0.15) // gray
    }
  }

  private var foreground: Color {
    switch status {
    case .notStarted: .orange
    case .inProgress: .green
    case .completed: .gray
    }
  }
}

// MARK: - TripEditForm (add/remove Classified Waters per angler)
// This is the full form from your project adapted to update trip.localUpdatedAt and
// post a notification when changes are saved so the TripListView refreshes.

private struct TripEditForm: View {
  @Environment(\.managedObjectContext) private var context
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var trip: Trip

  @State private var tripName = ""
  @State private var startDate = Date()
  @State private var endDate = Date()
  @State private var anglers: [TripClient] = []

  // Local draft for the visible Add Angler form
  @State private var newAnglerName = ""
  @State private var newLicense = ""
  @State private var newAnglerLicencesPreview: [ClassifiedLicenceDraft] = []

  // Per-angler inline "add licence" UI state keyed by TripClient.objectID
  @State private var expandedAdd: Set<NSManagedObjectID> = []
  @State private var newWater: [NSManagedObjectID: String] = [:]
  @State private var newLicNumber: [NSManagedObjectID: String] = [:]
  @State private var newFrom: [NSManagedObjectID: Date] = [:]
  @State private var newTo: [NSManagedObjectID: Date] = [:]

  // Delete confirmation
  @State private var deleteTarget: ClassifiedWaterLicense?

  // Track if changes have been made for Save button enable/disable
  @State private var hasChanges = false

  // The new behavior: pending in-memory new anglers that will be applied on Save
  struct NewAnglerDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var license: String = ""
    var licences: [ClassifiedLicenceDraft] = []
  }
  @State private var pendingAnglers: [NewAnglerDraft] = []
  
  // Added state for unsaved changes alert
  @State private var showUnsavedAlert = false

  // UI state for add-angler reveal & scanning
  @State private var showNewAnglerForm = false
  @State private var showScanChoice = false
  @State private var showScanCamera = false
  @State private var showScanLibrary = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      Form {
        Section(header: TripSectionHeader(title: "")) {
          HStack {
            Text("Lodge")
            Spacer()
            Text(trip.lodge?.name ?? "-")
              .foregroundColor(.secondary)
          }
          HStack {
            Text("Trip name")
            Spacer()
            TextField("Trip name", text: $tripName)
              .multilineTextAlignment(.trailing)
              .foregroundColor(.white)
              .onChange(of: tripName) { _ in hasChanges = true }
          }
        }

        datesSection()
          .onChange(of: startDate) { _ in hasChanges = true; trip.localUpdatedAt = Date() }
          .onChange(of: endDate) { _ in hasChanges = true; trip.localUpdatedAt = Date() }

        anglersSection()
          .onChange(of: newAnglerName) { _ in hasChanges = true; trip.localUpdatedAt = Date() }
          .onChange(of: newLicense) { _ in hasChanges = true; trip.localUpdatedAt = Date() }
      }
      .listStyle(.insetGrouped)
      .background(Color.black)
      .modifier(HideListBackgroundIfAvailable())
      .environment(\.colorScheme, .dark)
      .navigationTitle("Edit trip")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: saveChanges) {
            Text("Save")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14)
              .padding(.vertical, 6)
              .background(hasChanges ? Color.blue : Color.white.opacity(0.18))
              .clipShape(Capsule())
              .foregroundColor(.white)
          }
          .disabled(!hasChanges)
        }
      }
    }
    // Global alert for delete confirmation (presented when deleteTarget != nil)
    .alert("Delete Licence?", isPresented: Binding(
      get: { deleteTarget != nil },
      set: { if !$0 { deleteTarget = nil } }
    )) {
      Button("Delete", role: .destructive) {
        if let target = deleteTarget {
          deleteLicence(target)
          deleteTarget = nil
        }
      }
      Button("Cancel", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("This action cannot be undone.")
    }
    // Added alert for unsaved changes
    .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
      Button("Save Changes") {
        saveChanges()
      }
      Button("Discard", role: .destructive) {
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You have unsaved changes. What would you like to do?")
    }
    .onAppear {
      loadExistingValues()
    }
    // Scan flow (for new angler upload)
    .confirmationDialog(
      "Scan Angler License",
      isPresented: $showScanChoice,
      titleVisibility: .visible
    ) {
      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        Button("Camera") { showScanCamera = true }
      }
      Button("Photo Library") { showScanLibrary = true }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(isPresented: $showScanCamera) {
      ImagePicker(source: .camera) { picked in
        handleScannedImageForNewAngler(picked.image)
      }
    }
    .sheet(isPresented: $showScanLibrary) {
      ImagePicker(source: .library) { picked in
        handleScannedImageForNewAngler(picked.image)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder private func datesSection() -> some View {
    Section(header: TripSectionHeader(title: "Trip dates")) {
      DatePicker("Start date", selection: $startDate, displayedComponents: .date)
      DatePicker("End date", selection: $endDate, displayedComponents: .date)
    }
  }

  @ViewBuilder private func anglersSection() -> some View {
    Section(header: TripSectionHeader(title: "Anglers")) {
      if anglers.isEmpty {
        Text("No anglers added yet.").foregroundColor(.secondary)
      } else {
        // NOTE: we use value array, not binding array
        ForEach(anglers, id: \.objectID) { angler in
          VStack(alignment: .leading, spacing: 10) {
            // Header row with editable name/license & remove-angler button
            HStack {
              TextField("Angler Name", text: Binding(
                get: { angler.name ?? "" },
                set: { newVal in
                  angler.name = newVal
                  trip.localUpdatedAt = Date()
                  hasChanges = true
                }
              ))
              .textInputAutocapitalization(.words)

              Spacer().frame(width: 12)

              TextField("License Number", text: Binding(
                get: { angler.licenseNumber ?? "" },
                set: { newVal in
                  angler.licenseNumber = newVal
                  trip.localUpdatedAt = Date()
                  hasChanges = true
                }
              ))
              .textInputAutocapitalization(.characters)
              .disableAutocorrection(true)

              Spacer()

              Button(role: .destructive) {
                removeAngler(angler)
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.plain)
            }

            // --- Existing Classified Waters licences with delete buttons ---
            let rows = licenses(for: angler)
            if rows.isEmpty {
              Text("No Classified Waters licences.")
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              VStack(alignment: .leading, spacing: 6) {
                Text("Classified Waters")
                  .font(.caption).fontWeight(.semibold)
                  .foregroundColor(.secondary)

                ForEach(rows, id: \.objectID) { r in
                  HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(r.water ?? "—") • \(r.licNumber ?? "—")")
                        .font(.callout)
                      HStack(spacing: 8) {
                        if let from = r.validFrom {
                          Text("From: \(from.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                        }
                        if let to = r.validTo {
                          Text("To: \(to.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                        }
                      }
                    }
                    Spacer()
                    // Delete licence button (shows confirm)
                    Button(role: .destructive) {
                      deleteTarget = r
                    } label: {
                      Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete licence")
                  }
                  .padding(.vertical, 2)
                }
              }
              .padding(.top, 2)
            }

            // --- Add new Classified Waters licence (manual) ---
            let id = angler.objectID
            DisclosureGroup(
              isExpanded: Binding<Bool>(
                get: { expandedAdd.contains(id) },
                set: { isOn in
                  if isOn { _ = expandedAdd.insert(id) } else { expandedAdd.remove(id) }
                }
              ),
              content: {
                VStack(spacing: 8) {
                  TextField("Water (e.g., Nehalem River)", text: Binding(
                    get: { newWater[id, default: "" ] },
                    set: {
                      newWater[id] = $0
                      hasChanges = true
                      trip.localUpdatedAt = Date()
                    }
                  ))
                  TextField("Licence #", text: Binding(
                    get: { newLicNumber[id, default: "" ] },
                    set: {
                      newLicNumber[id] = $0
                      hasChanges = true
                      trip.localUpdatedAt = Date()
                    }
                  ))
                  HStack {
                    DatePicker("Valid From", selection: Binding(
                      get: { newFrom[id, default: Date()] },
                      set: {
                        newFrom[id] = $0
                        hasChanges = true
                        trip.localUpdatedAt = Date()
                      }
                    ), displayedComponents: .date)
                    DatePicker("Valid To", selection: Binding(
                      get: { newTo[id, default: Date()] },
                      set: {
                        newTo[id] = $0
                        hasChanges = true
                        trip.localUpdatedAt = Date()
                      }
                    ), displayedComponents: .date)
                  }

                  Button {
                    addLicence(for: angler)
                  } label: {
                    HStack { Spacer(); Text("Add License"); Spacer() }
                  }
                  .disabled(addDisabled(for: id))
                }
                .padding(.top, 6)
              },
              label: {
                Label("Add Classified Waters Licence", systemImage: "plus.circle")
                  .font(.callout)
              }
            )
            .onAppear {
              // Seed defaults the first time the group is opened for this client
              if newFrom[id] == nil { newFrom[id] = Date() }
              if newTo[id] == nil { newTo[id] = Date() }
            }
            // ----------------------------------------------------------
          }
          .padding(.vertical, 6)
        }
      }

      // MARK: - Pending new anglers (in-memory drafts)
      if !pendingAnglers.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("New anglers to be added on Save")
            .font(.caption)
            .foregroundColor(.secondary)
          ForEach(Array(pendingAnglers.enumerated()), id: \.element.id) { idx, draft in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                VStack(alignment: .leading) {
                  Text(draft.name.isEmpty ? "(Unnamed)" : draft.name)
                  if !draft.license.isEmpty {
                    Text("License: \(draft.license)").font(.caption).foregroundColor(.secondary)
                  }
                }
                Spacer()
                Button(role: .destructive) {
                  pendingAnglers.remove(at: idx)
                  hasChanges = true
                  trip.localUpdatedAt = Date()
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
              }

              if draft.licences.isEmpty {
                Text("No Classified Waters licences.")
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else {
                VStack(alignment: .leading, spacing: 6) {
                  Text("Classified Waters")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                  ForEach(draft.licences, id: \.id) { r in
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(r.water.isEmpty ? "—" : r.water) • \(r.licNumber)")
                        .font(.callout)
                      HStack(spacing: 8) {
                        if let from = r.validFrom {
                          Text("From: \(from.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                        }
                        if let to = r.validTo {
                          Text("To: \(to.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                        }
                      }
                    }
                    .padding(.vertical, 2)
                  }
                }
                .padding(.top, 2)
              }
            }
            .padding(.vertical, 4)
          }
        }
        .padding(.top, 6)
      }

      // Add new angler area: Button toggles reveal of the full add form
      VStack(spacing: 8) {
        if !showNewAnglerForm {
          Button {
            withAnimation { showNewAnglerForm = true }
          } label: {
            HStack {
              Spacer()
              Label("Add Angler", systemImage: "plus.circle.fill")
              Spacer()
            }
          }
        }

        if showNewAnglerForm {
          // Local draft inputs (these fields are per-form; pressing "Confirm" pushes into pendingAnglers)
          VStack(spacing: 8) {
            TextField("New Angler Name", text: $newAnglerName)
              .textInputAutocapitalization(.words)
              .onChange(of: newAnglerName) { _ in hasChanges = true; trip.localUpdatedAt = Date() }

            TextField("License Number", text: $newLicense)
              .textInputAutocapitalization(.characters)
              .disableAutocorrection(true)
              .onChange(of: newLicense) { _ in hasChanges = true; trip.localUpdatedAt = Date() }

            // Upload small-font button
            HStack {
              Button {
                showScanChoice = true
              } label: {
                Label("Upload License", systemImage: "camera.fill")
                  .font(.footnote) // smaller font per request
              }
              .buttonStyle(.bordered)

              Spacer()

              Button {
                Task { await lookupAndApplyDraft() }
              } label: {
                Label("Lookup", systemImage: "magnifyingglass")
                  .font(.footnote)
              }
              .buttonStyle(.bordered)
            }

            // Show previewed classified licences (if any) before user confirms
            if !newAnglerLicencesPreview.isEmpty {
              VStack(alignment: .leading, spacing: 6) {
                Text("Preview Classified Waters")
                  .font(.caption).fontWeight(.semibold)
                  .foregroundColor(.secondary)
                ForEach(newAnglerLicencesPreview, id: \.id) { r in
                  VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.water.isEmpty ? "—" : r.water) • \(r.licNumber)")
                      .font(.callout)
                    HStack(spacing: 8) {
                      if let from = r.validFrom {
                        Text("From: \(from.formatted(date: .abbreviated, time: .omitted))")
                          .font(.caption)
                      }
                      if let to = r.validTo {
                        Text("To: \(to.formatted(date: .abbreviated, time: .omitted))")
                          .font(.caption)
                      }
                    }
                  }
                  .padding(.vertical, 2)
                }
              }
              .padding(.top, 6)
            }

            // Confirm / Cancel (replaces previous Add button)
            HStack(spacing: 12) {
              Button(role: .cancel) {
                // Clear the draft and hide form
                newAnglerName = ""
                newLicense = ""
                newAnglerLicencesPreview = []
                withAnimation { showNewAnglerForm = false }
              } label: {
                HStack { Spacer(); Text("Cancel"); Spacer() }
              }
              .buttonStyle(.bordered)

              Button {
                confirmAddDraftAngler()
              } label: {
                HStack { Spacer(); Text("Confirm"); Spacer() }
              }
              .buttonStyle(.borderedProminent)
              .tint(.blue)
              .disabled(newAnglerName.trimmingCharacters(in: .whitespaces).isEmpty || newLicense.trimmingCharacters(in: .whitespaces).isEmpty || totalAnglerCountExceeded())
            }
            .padding(.top, 6)
          }
          .padding(.top, 6)
        }
      }
      .padding(.top, 6)
    }
  }

  // MARK: - Logic

  private func loadExistingValues() {
    tripName = trip.name ?? ""
    startDate = trip.startDate ?? Date()
    endDate = trip.endDate ?? Date()

    let set = trip.clients as? Set<TripClient> ?? []
    anglers = set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    hasChanges = false
  }

  private func totalAnglerCountExceeded() -> Bool {
    let existing = (trip.clients as? Set<TripClient>)?.count ?? 0
    return (existing + pendingAnglers.count) >= 8
  }

  /// Called when user presses Confirm. Adds the visible draft as a pending angler (with any parsed licences),
  /// clears the draft inputs, and leaves the pending angler visible in the list. These will be saved to Core Data on Save.
  private func confirmAddDraftAngler() {
    guard !newAnglerName.trimmingCharacters(in: .whitespaces).isEmpty,
          !newLicense.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    guard !totalAnglerCountExceeded() else { return }

    let draft = NewAnglerDraft(
      name: newAnglerName.trimmingCharacters(in: .whitespacesAndNewlines),
      license: newLicense.trimmingCharacters(in: .whitespacesAndNewlines),
      licences: newAnglerLicencesPreview
    )
    pendingAnglers.append(draft)

    // Clear local draft and hide form
    newAnglerName = ""
    newLicense = ""
    newAnglerLicencesPreview = []
    withAnimation { showNewAnglerForm = false }

    hasChanges = true
    trip.localUpdatedAt = Date()
  }

  // Existing addAngler preserved but not used for the new flow. Kept for compatibility.
  private func addAngler() {
    let newClient = TripClient(context: context)
    newClient.name = newAnglerName.trimmingCharacters(in: .whitespaces)
    newClient.licenseNumber = newLicense.trimmingCharacters(in: .whitespaces)
    newClient.trip = trip
    do {
      try context.save()
      trip.localUpdatedAt = Date()
      NotificationCenter.default.post(name: .tripDidChange, object: nil)
      anglers.append(newClient)
      newAnglerName = ""
      newLicense = ""
      hasChanges = true
    } catch {
      print("Failed to add angler:", error)
    }
  }

  private func removeAngler(_ angler: TripClient) {
    context.delete(angler) // cascade/nullify per model
    do {
      try context.save()
      trip.localUpdatedAt = Date()
      NotificationCenter.default.post(name: .tripDidChange, object: nil)
      anglers.removeAll { $0.objectID == angler.objectID }
      hasChanges = true
    } catch {
      print("Failed to remove angler:", error)
    }
  }

  // Query licences (same as detail)
  private func licenses(for client: TripClient) -> [ClassifiedWaterLicense] {
    let set = client.classifiedLicenses as? Set<ClassifiedWaterLicense> ?? []
    return set.sorted { a, b in
      let aFrom = a.validFrom ?? .distantPast
      let bFrom = b.validFrom ?? .distantPast
      if aFrom != bFrom { return aFrom < bFrom }
      return (a.water ?? "") < (b.water ?? "")
    }
  }

  // Validation for add form
  private func addDisabled(for id: NSManagedObjectID) -> Bool {
    let water = newWater[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    let num = newLicNumber[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    return water.isEmpty || num.isEmpty
  }

  // Add licence implementation (no Guide/Vendor)
  private func addLicence(for client: TripClient) {
    let id = client.objectID
    let water = newWater[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    let num = newLicNumber[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    let from = newFrom[id, default: Date()]
    let to = newTo[id, default: Date()]

    guard !water.isEmpty, !num.isEmpty else { return }

    let lic = ClassifiedWaterLicense(context: context)
    lic.water = water
    lic.licNumber = num
    lic.validFrom = from
    lic.validTo = to

    // Relationship: ensure this matches your model
    lic.client = client // inverse of client.classifiedLicenses

    do {
      try context.save()
      // update localUpdatedAt & notify
      trip.localUpdatedAt = Date()
      NotificationCenter.default.post(name: .tripDidChange, object: nil)

      // Clear the inline add form for this client
      newWater[id] = ""; newLicNumber[id] = ""
      newFrom[id] = Date(); newTo[id] = Date()
      hasChanges = true
    } catch {
      print("Failed to add licence:", error)
    }
  }

  // Delete licence with confirm
  private func deleteLicence(_ lic: ClassifiedWaterLicense) {
    context.delete(lic)
    do {
      try context.save()
      trip.localUpdatedAt = Date()
      NotificationCenter.default.post(name: .tripDidChange, object: nil)
      hasChanges = true
    } catch {
      print("Failed to delete licence:", error)
    }
  }

  private func saveChanges() {
    let beforeCount = (trip.clients as? Set<TripClient>)?.count ?? -1
    AppLogging.log({ "[TripEditForm] saveChanges – before save clients count: \(beforeCount) for trip=\(trip.objectID)" }, level: .debug, category: .trip)

    AppLogging.log("[TripEditForm] Applying pendingAnglers count: \(pendingAnglers.count)", level: .debug, category: .trip)
    for (idx, d) in pendingAnglers.enumerated() {
      AppLogging.log("[TripEditForm] Pending[\(idx)] name=\(d.name), license=\(d.license), licences=\(d.licences.count)", level: .debug, category: .trip)
    }

    trip.name = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
    trip.startDate = startDate
    trip.endDate = endDate

    // Helper to normalize and split a full name into first/last.
    // Collapses internal whitespace and trims edges so we never end up with nils due to stray spaces.
    func splitName(_ fullName: String) -> (first: String, last: String?) {
      // Trim and collapse multiple spaces/newlines into single spaces
      let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
      // Split on any whitespace and filter empties
      let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard let first = parts.first else { return ("", nil) }
      if parts.count == 1 {
        // Single token name: send as first name; omit last name
        return (first, nil)
      } else {
        // Join remaining tokens for last name to preserve middle/compound surnames
        let last = parts.dropFirst().joined(separator: " ")
        return (first, last.isEmpty ? nil : last)
      }
    }

    // Apply pendingAnglers to Core Data BEFORE saving
    for draft in pendingAnglers {
      let newClient = TripClient(context: context)
      newClient.name = draft.name
      newClient.licenseNumber = draft.license
      newClient.trip = trip

      // Persist classified licences from the draft, if any
      for c in draft.licences {
        let lic = ClassifiedWaterLicense(context: context)
        lic.water = c.water
        lic.licNumber = c.licNumber
        lic.validFrom = c.validFrom
        lic.validTo = c.validTo
        lic.client = newClient
      }
    }

    // IMPORTANT: set localUpdatedAt when the user explicitly saves the TripEditForm
    trip.localUpdatedAt = Date()

    let preSaveClients = pendingAnglers.map { ($0.name, $0.license, $0.licences.count) }
    AppLogging.log("[TripEditForm] Pre-save snapshot — new clients: \(preSaveClients)", level: .debug, category: .trip)

    do {
      try context.save()
      hasChanges = false
      // notify that trip changed so TripListView can refresh
      NotificationCenter.default.post(name: .tripDidChange, object: nil)

      Task { @MainActor in
        await AuthStore.shared.refreshFromSupabase()
        guard let jwt = AuthStore.shared.jwt else {
          AppLogging.log("[TripEditForm] Upload skipped: not signed in", level: .info, category: .trip)
          return
        }

        // Build anglers payload from current Core Data values
        let clientsSet = (trip.clients as? Set<TripClient>) ?? []

        let rawClientsSnapshot: [[String: Any]] = clientsSet.map { c in
          [
            "name": (c.name ?? ""),
            "licenseNumber": (c.licenseNumber ?? "")
          ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: rawClientsSnapshot, options: [.prettyPrinted]), let text = String(data: data, encoding: .utf8) {
          AppLogging.log("[TripEditForm] Raw clients snapshot before payload build:\n\(text)", level: .debug, category: .trip)
        }

        let anglersPayload: [TripAPI.UpsertTripRequest.UpsertAngler] = clientsSet.map { client in
          // Split client's full name into first/last with normalization to avoid nils from stray spaces
          let normalized = (client.name ?? "")
          let split = splitName(normalized)
          let firstName: String? = split.first.isEmpty ? nil : split.first
          let lastName: String? = split.last

          AppLogging.log("[TripEditForm] Mapping client — rawName='\(client.name ?? "")', first='\(firstName ?? "<nil>")', last='\(lastName ?? "<nil>")', anglerNumber='\((client.licenseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines))'", level: .debug, category: .trip)

          let licSet = (client.classifiedLicenses as? Set<ClassifiedWaterLicense>) ?? []
          let licenses: [TripAPI.UpsertTripRequest.UpsertAngler.UpsertLicense] = licSet.compactMap { lic in
            guard let from = lic.validFrom, let to = lic.validTo else { return nil }
            return .init(
              licenseNumber: lic.licNumber ?? "",
              riverName: lic.water ?? "",
              startDate: from.yyyyMMdd,
              endDate: to.yyyyMMdd
            )
          }

          return .init(
            anglerNumber: (client.licenseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: nil,
            residency: nil,
            sex: nil,
            mailingAddress: nil,
            telephoneNumber: nil,
            classifiedWatersLicenses: licenses.isEmpty ? nil : licenses
          )
        }

        let payloadPreview = anglersPayload.prefix(3).map { a in
          [
            "anglerNumber": a.anglerNumber,
            "firstName": a.firstName as Any,
            "lastName": a.lastName as Any,
            "licensesCount": a.classifiedWatersLicenses?.count as Any
          ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payloadPreview, options: [.prettyPrinted]), let text = String(data: data, encoding: .utf8) {
          AppLogging.log("[TripEditForm] Anglers payload preview (first up to 3):\n\(text)", level: .debug, category: .trip)
        }

        let communityValue: String = {
          let attrs = trip.entity.attributesByName
          if attrs["community"] != nil,
             let c = trip.value(forKey: "community") as? String,
             !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return c
          }
          return AppEnvironment.shared.communityName
        }()

        let upsert = TripAPI.UpsertTripRequest(
          tripId: trip.tripId?.uuidString ?? UUID().uuidString,
          tripName: trip.name ?? "",
          startDate: (trip.startDate ?? Date()).iso8601ZString,
          endDate: (trip.endDate ?? Date()).iso8601ZString,
          guideName: trip.guideName ?? "",
          clientName: nil,
          community: communityValue,
          lodge: trip.lodge?.name,
          anglers: anglersPayload
        )
        AppLogging.log("[TripEditForm] Upsert summary — tripId=\(upsert.tripId), tripName=\(upsert.tripName), start=\(upsert.startDate ?? "<nil>"), end=\(upsert.endDate ?? "<nil>"), guide=\(upsert.guideName ?? "<nil>"), community=\(upsert.community ?? "<nil>"), lodge=\(upsert.lodge ?? "<nil>"), anglers=\(upsert.anglers.count)", level: .debug, category: .trip)

        do {
          _ = try await TripAPI.upsertTrip(upsert, jwt: jwt)
          AppLogging.log("[TripEditForm] Upload succeeded for tripId=\(upsert.tripId)", level: .info, category: .trip)
        } catch {
          AppLogging.log("[TripEditForm] Upload failed for tripId=\(upsert.tripId): \(error.localizedDescription)", level: .error, category: .trip)
        }
      }

      dismiss()
    } catch {
      let failCount = (trip.clients as? Set<TripClient>)?.count ?? -1
      AppLogging.log("[TripEditForm] saveChanges – save failed, clients count: \(failCount) for trip=\(trip.objectID), error: \(error)", level: .error, category: .trip)
    }
  }

  // MARK: - OCR / Scan handling for the Add Angler flow
  // Uses the shared FSELicenseTextRecognizer so parsing matches TripFormView exactly.

  private func handleScannedImageForNewAngler(_ image: UIImage) {
    FSELicenseTextRecognizer.recognize(in: image, options: .init()) { result in
      DispatchQueue.main.async {
        if let parsedName = result.name, !parsedName.trimmingCharacters(in: .whitespaces).isEmpty {
          newAnglerName = parsedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parsedLicense = result.licenseNumber, !parsedLicense.trimmingCharacters(in: .whitespaces).isEmpty {
          newLicense = parsedLicense.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !result.classifiedLicences.isEmpty {
          let converted: [ClassifiedLicenceDraft] = result.classifiedLicences.map { parsed in
            ClassifiedLicenceDraft(
              licNumber: parsed.licNumber,
              water: parsed.water,
              validFrom: parsed.validFrom,
              validTo: parsed.validTo,
              guideName: parsed.guideName,
              vendor: parsed.vendor
            )
          }
          // Show parsed licences in preview for the visible draft
          newAnglerLicencesPreview = converted
        }

        hasChanges = true
        trip.localUpdatedAt = Date()
      }
    }
  }

  // Basic Angler lookup for the local draft (calls AnglerAPI similarly to TripFormView)
  private func lookupAndApplyDraft() async {
    await AuthStore.shared.refreshFromSupabase()
    guard let jwt = AuthStore.shared.jwt else {
      return
    }
    do {
      let results = try await AnglerAPI.search(anglerNumber: newLicense, anglerName: newAnglerName, jwt: jwt)
      guard !results.isEmpty else {
        print("[TripEditForm] lookup: no angler found")
        return
      }
      // For the new-angler flow, prefer the first match for simplicity (TripFormView shows a candidate picker)
      let profile = results[0]
      DispatchQueue.main.async {
        newAnglerName = profile.anglerName
        newLicense = profile.anglerNumber
        newAnglerLicencesPreview = profile.classifiedWatersLicenses.map { lic in
          ClassifiedLicenceDraft(
            licNumber: lic.license_number,
            water: lic.river_name,
            validFrom: parseYMD(lic.start_date),
            validTo: parseYMD(lic.end_date),
            guideName: "",
            vendor: ""
          )
        }
        hasChanges = true
        trip.localUpdatedAt = Date()
      }
    } catch {
      print("[TripEditForm] Lookup failed: \(error)")
    }
  }

  // Helper to fetch pendingAnglers from any cached state if needed.
  private func loadPendingIfNeeded() {
    // No-op currently; kept for extension if you persist previews across navigation
  }

  // Simple YYYY-MM-DD parser used when mapping AnglerAPI results
  private func parseYMD(_ s: String) -> Date? {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: s)
  }
}

// MARK: - Small helper

private func dayString(_ date: Date?) -> String {
  guard let d = date else { return "-" }
  return d.formatted(date: .abbreviated, time: .omitted)
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

// MARK: - TripSectionHeader helper used in TripEditForm

private struct TripSectionHeader: View {
  let title: String
  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .fontWeight(.semibold)
      Spacer()
    }
    .padding(.vertical, 2)
  }
}

// MARK: - View extension to safely apply iOS16 toolbarBackground modifiers

private extension View {
  @ViewBuilder
  func applyNavigationBarToolbarBackground() -> some View {
    if #available(iOS 16.0, *) {
      self.toolbarBackground(Color.black, for: .navigationBar)
          .toolbarBackground(.visible, for: .navigationBar)
    } else {
      self
    }
  }
}

private extension Date {
  var iso8601ZString: String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: self)
  }
  var yyyyMMdd: String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: self)
  }
}
