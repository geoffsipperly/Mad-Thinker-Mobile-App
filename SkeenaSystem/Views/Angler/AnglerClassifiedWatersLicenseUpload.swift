// Bend Fly Shop

import Foundation
import SwiftUI
import UIKit
import Vision
import WebKit

struct AnglerClassifiedWatersLicenseUpload: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared

  private var anglerNumber: String? { auth.currentAnglerNumber }

  // Server list
  @State private var licenses: [CWLicenseDTO] = []

  // UI state
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var infoText: String?

  // New rows (POST)
  @State private var pendingRows: [EditableClassifiedRow] = []

  // Edits (PUT): license id -> editable copy
  @State private var pendingEdits: [String: EditableClassifiedRow] = [:]

  // Deletes (DELETE): ids flagged
  @State private var pendingDeletes: Set<String> = []

  // Confirm leaving with unsaved changes
  @State private var showUnsavedConfirm = false

  // Manual entry
  @State private var showManual = false
  @State private var manual = EditableClassifiedRow(
    licNumber: "",
    water: "",
    fromDate: Date(),
    toDate: Date().addingTimeInterval(24 * 3600)
  )

  // Scan flow
  @State private var showScanChoice = false
  @State private var showScanCamera = false
  @State private var showScanLibrary = false

  private var hasUnsavedChanges: Bool {
    !pendingRows.isEmpty || !pendingEdits.isEmpty || !pendingDeletes.isEmpty
  }

  // MARK: - Body

  var body: some View {
    mainContent
      .background(Color.black.ignoresSafeArea())
      .task {
        if !isLoading, let num = anglerNumber, !num.isEmpty {
          await fetchExisting(for: num)
        } else {
          errorText = "Missing angler number. Please sign in again."
        }
      }
      .navigationTitle("Classified Waters Licenses")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            if hasUnsavedChanges {
              showUnsavedConfirm = true
            } else {
              dismiss()
            }
          } label: {
            Image(systemName: "chevron.left")
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            Task { await saveAll() }
          } label: {
            HStack(spacing: 6) {
              if isLoading { ProgressView() }
              Text("Save")
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(.white)
            .background((hasUnsavedChanges && !isLoading) ? Color.blue : Color.white.opacity(0.15))
            .clipShape(Capsule())
          }
          .tint(.blue)
          .disabled(!hasUnsavedChanges || isLoading)
        }
      }
      .confirmationDialog(
        "You have unsaved changes",
        isPresented: $showUnsavedConfirm,
        titleVisibility: .visible
      ) {
        Button("Save") {
          Task { await saveAll(thenDismiss: true) }
        }
        Button("Discard Changes", role: .destructive) {
          withAnimation {
            pendingRows.removeAll()
            pendingEdits.removeAll()
            pendingDeletes.removeAll()
          }
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      }
      // Manual entry sheet
      .sheet(isPresented: $showManual) {
        manualEntrySheet
      }
      // Scan chooser + sheets
      .confirmationDialog(
        "Scan Classified Licence",
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
        // ImagePicker now returns PickedPhoto → we only need the UIImage for OCR
        ImagePicker(source: .camera) { picked in
          Task { await handleScannedImage(picked.image) }
        }
      }
      .sheet(isPresented: $showScanLibrary) {
        ImagePicker(source: .library) { picked in
          Task { await handleScannedImage(picked.image) }
        }
      }
      .preferredColorScheme(.dark)
  }

  // MARK: - Composed content

  private var mainContent: some View {
    VStack(spacing: 12) {
      headerMessages
      licenseList
    }
  }

  @ViewBuilder
  private var headerMessages: some View {
    if let err = errorText {
      Text(err)
        .foregroundColor(.red)
        .font(.footnote)
        .padding(.horizontal)
    }
    if let info = infoText {
      Text(info)
        .foregroundColor(.gray)
        .font(.footnote)
        .padding(.horizontal)
    }

    Text("As of \(Date.now.formatted(date: .long, time: .omitted))")
      .font(.footnote.weight(.semibold))
      .foregroundColor(.gray)
      .padding(.top, 4)

    Text("Note: Swipe left to edit or modify a license")
      .font(.footnote.weight(.thin))
      .foregroundColor(.white)
      .padding(.top, 6)
  }

  private var licenseList: some View {
    List {
      licenseListContent
    }
    .listStyle(.insetGrouped)
    .background(Color.black)
  }

  @ViewBuilder
  private var licenseListContent: some View {
    if let angler = anglerNumber, !angler.isEmpty {
      let grouped = groupLicenses(licenses)

      if !grouped.active.isEmpty {
        Section(header: sectionHeader("Active")) {
          ForEach(grouped.active) { l in
            licenseCell(l)
          }
        }
      }

      if !grouped.future.isEmpty {
        Section(header: sectionHeader("Future")) {
          ForEach(grouped.future) { l in
            licenseCell(l)
          }
        }
      }

      if !grouped.expired.isEmpty {
        Section(header: sectionHeader("Expired")) {
          ForEach(grouped.expired) { l in
            licenseCell(l)
          }
        }
      }

      if !pendingRows.isEmpty {
        Section(header: sectionHeader("New (Unsaved)")) {
          ForEach($pendingRows) { $row in
            editableRow($row)
          }
          .onDelete { idx in
            pendingRows.remove(atOffsets: idx)
          }
        }
      }

      Section(header: sectionHeader("Add Classified License")) {
        Button {
          manual = EditableClassifiedRow(
            licNumber: "",
            water: "",
            fromDate: Date(),
            toDate: Date().addingTimeInterval(24 * 3600)
          )
          showManual = true
        } label: {
          HStack {
            Image(systemName: "square.and.pencil")
            Text("Manual Entry")
            Spacer()
          }
        }

        Button {
          showScanChoice = true
        } label: {
          HStack {
            Image(systemName: "text.viewfinder")
            Text("Scan")
            Spacer()
          }
        }

        NavigationLink {
          BuyLicensesPage(
            title: "Buy Licenses",
            url: URL(string: "https://j100.gov.bc.ca/pub/ras/signin.aspx")!
          )
          .preferredColorScheme(.dark)
        } label: {
          HStack {
            Image(systemName: "cart.badge.plus")
            Text("Buy a new license")
            Spacer()
          }
        }
      }
    } else {
      Section {
        Text("Missing angler number. Please sign in again.")
          .font(.footnote)
          .foregroundColor(.gray)
      }
    }
  }

  // MARK: - Manual entry sheet

  private var manualEntrySheet: some View {
    NavigationView {
      VStack(spacing: 14) {
        formRowEditor($manual)
          .padding(.top, 8)
        
        let isValid = !manual.licNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
          !manual.water.trimmingCharacters(in: .whitespaces).isEmpty &&
          manual.toDate >= manual.fromDate

        Spacer()

        Button {
          pendingRows.append(manual)
          showManual = false
        } label: {
          Text("Add")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.white)
            .background(isValid ? Color.blue : Color.white.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .disabled(!isValid)
      }
      .padding(.horizontal)
      .navigationTitle("Add Classified Waters License")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") { showManual = false }
        }
      }
      .background(Color.black.ignoresSafeArea())
    }
    .preferredColorScheme(.dark)
  }

  // MARK: Section header

  private func sectionHeader(_ title: String) -> some View {
    Text(title.uppercased())
      .font(.caption.weight(.semibold))
      .foregroundColor(.gray)
  }

  // MARK: Row (existing item – display, edit, delete)

  @ViewBuilder
  private func licenseCell(_ l: CWLicenseDTO) -> some View {
    let isDeleted = pendingDeletes.contains(l.id)
    let bgColor = Color.white.opacity(0.05)

    if pendingEdits[l.id] != nil {
      let binding = bindingForEdit(id: l.id)

      editableRow(binding)
        .overlay(alignment: .topTrailing) {
          Button {
            withAnimation {
              _ = pendingEdits.removeValue(forKey: l.id)
            }
          } label: {
            Text("Cancel")
              .font(.footnote)
              .foregroundColor(.blue)
          }
          .padding(.top, 2)
        }
        .listRowBackground(bgColor)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button("Done") { /* edits are saved via Save button */ }
            .tint(.blue)
        }

    } else {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(l.license_number)
            .font(.headline)
            .foregroundColor(.white)
            .strikethrough(isDeleted)

          Spacer()

          Text("\(fmtDate(l.start_date)) – \(fmtDate(l.end_date))")
            .font(.footnote)
            .foregroundColor(.gray)
        }

        Text(l.river_name)
          .font(.subheadline)
          .foregroundColor(.white)
          .strikethrough(isDeleted)
      }
      .listRowBackground(bgColor)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button("Edit") {
          withAnimation {
            pendingEdits[l.id] = EditableClassifiedRow(
              licNumber: l.license_number,
              water: l.river_name,
              fromDate: parseYMD(l.start_date) ?? Date(),
              toDate: parseYMD(l.end_date) ?? Date()
            )
          }
        }
        .tint(.blue)

        Button(role: isDeleted ? .cancel : .destructive) {
          withAnimation {
            if isDeleted {
              _ = pendingDeletes.remove(l.id)
            } else {
              _ = pendingDeletes.insert(l.id)
            }
          }
        } label: {
          Text(isDeleted ? "Undo" : "Delete")
        }
      }
    }
  }

  // Reused editor for new & edited rows
  private func editableRow(_ row: Binding<EditableClassifiedRow>) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Licence #", text: row.licNumber)
        .textInputAutocapitalization(.never)
        .keyboardType(.asciiCapable)
        .foregroundColor(.white)

      TextField("Water", text: row.water)
        .foregroundColor(.white)

      HStack(spacing: 10) {
        DatePicker("From", selection: row.fromDate, displayedComponents: .date)
          .labelsHidden()
        DatePicker("To", selection: row.toDate, displayedComponents: .date)
          .labelsHidden()
      }
    }
  }

  private func formRowEditor(_ row: Binding<EditableClassifiedRow>) -> some View {
    Group {
      TextField("Licence #", text: row.licNumber)
        .textInputAutocapitalization(.never)
        .keyboardType(.asciiCapable)
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .foregroundColor(.white)

      TextField("Water (river name)", text: row.water)
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .foregroundColor(.white)

      HStack(spacing: 10) {
        DatePicker("Start", selection: row.fromDate, displayedComponents: .date)
          .labelsHidden()
          .padding()
          .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

        DatePicker("End", selection: row.toDate, displayedComponents: .date)
          .labelsHidden()
          .padding()
          .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  // MARK: API Calls

  private func fetchExisting(for angler: String) async {
    guard !isLoading else { return }
    isLoading = true
    errorText = nil
    infoText = "Loading…"
    defer { isLoading = false }

    do {
      let tokenOpt = await auth.currentAccessToken()
      guard let t1 = tokenOpt, !t1.isEmpty else {
        throw NSError(
          domain: "CWAPI",
          code: 401,
          userInfo: [NSLocalizedDescriptionKey: "Missing token"]
        )
      }

      do {
        let fetched = try await ClassifiedLicenceAPI.getLicenses(
          token: t1,
          apikey: auth.publicAnonKey,
          anglerNumber: angler
        )
        withAnimation {
          licenses = fetched
          infoText = nil
        }
        return
      } catch let e as NSError where e.code == 401 || e.code == 403 {
        _ = await auth.currentAccessToken()
        let t2 = await auth.currentAccessToken()
        guard let t2, !t2.isEmpty, t2 != t1 else { throw e }
        let fetched = try await ClassifiedLicenceAPI.getLicenses(
          token: t2,
          apikey: auth.publicAnonKey,
          anglerNumber: angler
        )
        withAnimation {
          licenses = fetched
          infoText = nil
        }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  // Save creates + edits + deletes in one pass with the updated API
  private func saveAll(thenDismiss: Bool = false) async {
    guard let angler = anglerNumber, !angler.isEmpty else {
      errorText = "Missing angler number. Please sign in again."
      return
    }
    guard hasUnsavedChanges else {
      if thenDismiss { dismiss() }
      return
    }

    isLoading = true
    errorText = nil
    infoText = "Saving…"
    defer { isLoading = false }

    do {
      let tokenOpt = await auth.currentAccessToken()
      guard let token = tokenOpt, !token.isEmpty else {
        throw NSError(
          domain: "CWAPI",
          code: 401,
          userInfo: [NSLocalizedDescriptionKey: "Missing token"]
        )
      }

      // 1) CREATE (POST)
      var created: [CWLicenseDTO] = []
      for row in pendingRows {
        let dto = try await ClassifiedLicenceAPI.createLicense(
          token: token,
          apikey: auth.publicAnonKey,
          anglerNumber: angler,
          licenseNumber: row.licNumber,
          riverName: row.water,
          startDate: ymd(row.fromDate),
          endDate: ymd(row.toDate)
        )
        created.append(dto)
      }

      // 2) UPDATE (PUT)
      var updated: [CWLicenseDTO] = []
      for (id, row) in pendingEdits {
        let dto = try await ClassifiedLicenceAPI.updateLicense(
          token: token,
          apikey: auth.publicAnonKey,
          licenseId: id,
          licenseNumber: row.licNumber,
          riverName: row.water,
          startDate: ymd(row.fromDate),
          endDate: ymd(row.toDate)
        )
        updated.append(dto)
      }

      // 3) DELETE (DELETE with ?licenseId=)
      for id in pendingDeletes {
        try await ClassifiedLicenceAPI.deleteLicense(
          token: token,
          apikey: auth.publicAnonKey,
          licenseId: id
        )
      }

      // Optimistic local reconcile
      withAnimation {
        licenses.removeAll { pendingDeletes.contains($0.id) }
        for u in updated {
          if let i = licenses.firstIndex(where: { $0.id == u.id }) {
            licenses[i] = u
          }
        }
        licenses.append(contentsOf: created)

        pendingRows.removeAll()
        pendingEdits.removeAll()
        pendingDeletes.removeAll()
      }

      // small settle then refresh
      try? await Task.sleep(nanoseconds: 400_000_000)
      await fetchExisting(for: angler)

      infoText = "Saved."
      if thenDismiss { dismiss() }

    } catch {
      errorText = error.localizedDescription
    }
  }

  // MARK: OCR handling

  private func handleScannedImage(_ image: UIImage?) async {
    guard let uiImage = image, let cg = uiImage.cgImage else { return }
    errorText = nil
    infoText = "Scanning…"

    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    req.recognitionLanguages = ["en-CA", "en-US"]

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
      try handler.perform([req])
    } catch {
      self.errorText = "Text recognition failed: \(error.localizedDescription)"
      self.infoText = nil
      return
    }

    let observations = req.results ?? []
    var lines: [OCRLine] = []
    for obs in observations {
      guard let candidate = obs.topCandidates(1).first else { continue }
      lines.append(
        OCRLine(text: candidate.string, bbox: obs.boundingBox, confidence: candidate.confidence)
      )
    }

    let parsed = BCClassifiedWaters.parse(lines: lines)
    let now = Date()
    let newRows = parsed.map {
      EditableClassifiedRow(
        licNumber: $0.licNumber,
        water: $0.water,
        fromDate: $0.validFrom ?? now,
        toDate: $0.validTo ?? now
      )
    }
    guard !newRows.isEmpty else {
      errorText = "No licence rows detected. Try a clearer image."
      return
    }
    withAnimation {
      pendingRows.append(contentsOf: newRows)
      infoText = "Parsed \(newRows.count) row(s). Review and tap Save."
    }
  }

  // MARK: Helpers

  private func ymd(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.string(from: date)
  }

  private func parseYMD(_ s: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: s)
  }

  private func fmtDate(_ ymd: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    if let d = f.date(from: ymd) {
      let out = DateFormatter()
      out.dateStyle = .medium
      return out.string(from: d)
    }
    return ymd
  }

  /// Groups using string comparisons on `yyyy-MM-dd` in UTC.
  /// `end_date` is **exclusive**.
  private func groupLicenses(_ items: [CWLicenseDTO])
    -> (active: [CWLicenseDTO], future: [CWLicenseDTO], expired: [CWLicenseDTO]) {
    let todayStr = ymd(Date())
    var active: [CWLicenseDTO] = []
    var future: [CWLicenseDTO] = []
    var expired: [CWLicenseDTO] = []

    for l in items {
      let s = l.start_date
      let e = l.end_date

      if s > todayStr {
        future.append(l)
      } else if todayStr < e {
        active.append(l)
      } else {
        expired.append(l)
      }
    }
    active.sort { $0.start_date < $1.start_date }
    future.sort { $0.start_date < $1.start_date }
    expired.sort { $0.end_date > $1.end_date }
    return (active, future, expired)
  }

  // Build a stable Binding outside ViewBuilder inference path
  private func bindingForEdit(id: String) -> Binding<EditableClassifiedRow> {
    let fallback = pendingEdits[id] ?? EditableClassifiedRow(
      licNumber: "",
      water: "",
      fromDate: Date(),
      toDate: Date().addingTimeInterval(24 * 3600)
    )
    return Binding<EditableClassifiedRow>(
      get: { pendingEdits[id] ?? fallback },
      set: { pendingEdits[id] = $0 }
    )
  }
}

// MARK: Unique web wrappers (avoid 'WebView' name collisions elsewhere)

struct EmbeddedWKWebView: UIViewRepresentable {
  let url: URL
  @Binding var isLoading: Bool

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsBackForwardNavigationGestures = true
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear

    // initial load
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    // no-op for now
  }

  class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let parent: EmbeddedWKWebView
    init(_ parent: EmbeddedWKWebView) { self.parent = parent }

    // Keep target=_blank links inside this web view
    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }

    // Loading state
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      parent.isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      parent.isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      parent.isLoading = false
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      parent.isLoading = false
    }
  }
}

struct BuyLicensesPage: View {
  let title: String
  let url: URL

  @Environment(\.dismiss) private var dismiss
  @State private var isLoading = true

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        // Custom in-app header
        HStack {
          Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
              .font(.headline)
          }

          Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .center)

          Button {
            UIApplication.shared.open(url)
          } label: {
            Image(systemName: "safari")
              .font(.headline)
          }
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .foregroundColor(.white)

        // Web content with loading overlay
        ZStack {
          EmbeddedWKWebView(url: url, isLoading: $isLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)

          if isLoading {
            VStack {
              ProgressView("Loading…")
                .progressViewStyle(.circular)
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.4))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationBarHidden(true) // we’re using our own header
  }
}

// MARK: Models

struct CWLicenseDTO: Codable, Identifiable, Hashable {
  let id: String
  let angler_id: String
  let license_number: String
  let river_name: String
  let start_date: String // "yyyy-MM-dd" UTC
  let end_date: String // "yyyy-MM-dd" UTC (exclusive)
  let created_at: String
  let updated_at: String
}

struct EditableClassifiedRow: Identifiable, Hashable {
  let id = UUID()
  var licNumber: String
  var water: String
  var fromDate: Date
  var toDate: Date
}

// MARK: API

enum ClassifiedLicenceAPI {

  private static let rawBaseURLString: String = {
    (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }()

  private static let baseURLString: String = {
    var s = rawBaseURLString
    if !s.isEmpty, URL(string: s)?.scheme == nil {
      s = "https://" + s
    }
    return s
  }()

  private static let licensesPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "CLASSIFIED_LICENSES_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    ?? "/functions/v1/classified-licenses"
  }()

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString),
          let scheme = base.scheme,
          let host = base.host
    else {
      throw URLError(.badURL)
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    // allow API_BASE_URL to include an optional base path
    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    comps.path = normalizedBasePath + normalizedPath

    // preserve any query items already present in API_BASE_URL (rare, but safe)
    let existing = base.query != nil ? (URLComponents(string: base.absoluteString)?.queryItems ?? []) : []
    comps.queryItems = existing + queryItems

    guard let url = comps.url else { throw URLError(.badURL) }
    return url
  }

  static func url() throws -> URL {
    try makeURL(path: licensesPath)
  }

  // expose the composed base URL for existing callers
  static let base: URL = (try? ClassifiedLicenceAPI.url()) ?? URL(string: "https://invalid.local")!

  // Normalize token to avoid double "Bearer "
  private static func normalizedBearer(_ token: String) -> String {
    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.lowercased().hasPrefix("bearer ") { return String(t.dropFirst(7)) }
    return t
  }

  private static func makeRequest(
    url: URL,
    method: String,
    token: String,
    apikey: String,
    body: Data? = nil
  ) -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = method
    let clean = normalizedBearer(token)
    req.setValue("Bearer \(clean)", forHTTPHeaderField: "Authorization")
    req.setValue(apikey, forHTTPHeaderField: "apikey")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if method != "GET" && method != "DELETE" {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    req.setValue("ios:epic-waters", forHTTPHeaderField: "x-client-info")
    req.httpBody = body
    return req
  }

  // GET ?anglerNumber=...
  static func getLicenses(token: String, apikey: String, anglerNumber: String) async throws -> [CWLicenseDTO] {
    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "anglerNumber", value: anglerNumber)]

    let req = makeRequest(url: comps.url!, method: "GET", token: token, apikey: apikey)
    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard code == 200 else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "CWAPI",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: "Fetch failed (\(code)). \(body.isEmpty ? "<no body>" : body)"]
      )
    }
    struct Resp: Decodable { let success: Bool; let licenses: [CWLicenseDTO] }
    return try JSONDecoder().decode(Resp.self, from: data).licenses
  }

  // POST create
  static func createLicense(
    token: String,
    apikey: String,
    anglerNumber: String,
    licenseNumber: String,
    riverName: String,
    startDate: String,
    endDate: String
  ) async throws -> CWLicenseDTO {
    // IMPORTANT: use "endDate" (lowercase e) unless your server truly expects "EndDate"
    let bodyObj: [String: String] = [
      "anglerNumber": anglerNumber,
      "licenseNumber": licenseNumber,
      "riverName": riverName,
      "startDate": startDate,
      "endDate": endDate
    ]

    let req = makeRequest(
      url: base,
      method: "POST",
      token: token,
      apikey: apikey,
      body: try JSONSerialization.data(withJSONObject: bodyObj, options: [])
    )
    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard (200 ..< 300).contains(code) else {
      let msg = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "CWAPI",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: "Create failed (\(code)). \(msg.isEmpty ? "<no body>" : msg)"]
      )
    }
    struct Resp: Decodable { let success: Bool; let license: CWLicenseDTO }
    return try JSONDecoder().decode(Resp.self, from: data).license
  }

  // PUT update
  static func updateLicense(
    token: String,
    apikey: String,
    licenseId: String,
    licenseNumber: String?,
    riverName: String?,
    startDate: String?,
    endDate: String?
  ) async throws -> CWLicenseDTO {
    var bodyObj: [String: String] = ["licenseId": licenseId]
    if let licenseNumber { bodyObj["licenseNumber"] = licenseNumber }
    if let riverName { bodyObj["riverName"] = riverName }
    if let startDate { bodyObj["startDate"] = startDate }
    if let endDate { bodyObj["endDate"] = endDate }

    let req = makeRequest(
      url: base,
      method: "PUT",
      token: token,
      apikey: apikey,
      body: try JSONSerialization.data(withJSONObject: bodyObj, options: [])
    )
    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard code == 200 else {
      let msg = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "CWAPI",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: "Update failed (\(code)). \(msg.isEmpty ? "<no body>" : msg)"]
      )
    }
    struct Resp: Decodable { let success: Bool; let license: CWLicenseDTO }
    return try JSONDecoder().decode(Resp.self, from: data).license
  }

  // DELETE ?licenseId=...
  static func deleteLicense(token: String, apikey: String, licenseId: String) async throws {
    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "licenseId", value: licenseId)]
    var req = makeRequest(url: comps.url!, method: "DELETE", token: token, apikey: apikey)
    req.httpBody = nil

    let (_, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard code == 200 else {
      throw NSError(
        domain: "CWAPI",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: "Delete failed (\(code))."]
      )
    }
  }
}
