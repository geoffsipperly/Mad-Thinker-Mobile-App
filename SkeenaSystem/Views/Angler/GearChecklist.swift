// Bend Fly Shop
// GearChecklist.swift

import SwiftUI
import Foundation

private enum GearAPI {
  // Composable base + path URLs from Info.plist keys, fallback defaults

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

  private static let gearPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "GEAR_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/gear"
  }()

  private static func logConfig() {
    AppLogging.log("GearAPI config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .angler)
    AppLogging.log("GearAPI config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .angler)
    AppLogging.log("GearAPI config — GEAR_URL: '\(gearPath)'", level: .debug, category: .angler)
  }

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("GearAPI invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .debug, category: .angler)
      throw NSError(domain: "GearAPI", code: -1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API_BASE_URL (raw: '\(rawBaseURLString)', normalized: '\(baseURLString)')"])
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    comps.path = normalizedBasePath + normalizedPath

    let existing = base.query != nil ? URLComponents(string: base.absoluteString)?.queryItems ?? [] : []
    comps.queryItems = existing + queryItems

    guard let url = comps.url else {
      throw NSError(domain: "GearAPI", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Failed to build URL for path: \(path)"])
    }
    return url
  }

  static func gearURL() throws -> URL {
    logConfig()
    return try makeURL(path: gearPath)
  }
}

struct GearChecklist: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared

  // MARK: - State (placeholder for future API integration)
  @State private var mandatorySelections: Set<UUID> = []
  @State private var recommendedSelections: Set<UUID> = []
  @State private var reelHand: ReelHand = .right
  @State private var showOptional: Bool = false
  @State private var isDirty: Bool = false

  @State private var hasWaders: Bool = false
  @State private var hasBoots: Bool = false
  @State private var hasWadingJacket: Bool = false
  @State private var hasSwitchRod: Bool = false
  @State private var hasShortSpey: Bool = false

  @State private var isSaving: Bool = false
  @State private var errorText: String?
  @State private var infoText: String?

  @State private var showSaveAlert: Bool = false
  @State private var saveSucceeded: Bool = false

  private func cacheKey(anglerId: String, lodgeName: String) -> String { "gear_\(anglerId)_\(lodgeName)" }

  enum ReelHand: String, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  // MARK: - Data
  private let mandatoryItems: [ChecklistItem] = [
    ChecklistItem(title: "Waders", subtitle: "Preferably stocking foot for hiking"),
    ChecklistItem(title: "Boots", subtitle: "Vibram soled with cleats"),
    ChecklistItem(title: "Wading Jacket", subtitle: "Gore-tex or similar waterproof for rain protection")
  ]

  private let recommendedItems: [ChecklistItem] = [
    ChecklistItem(title: "Switch rod 11-12ft", subtitle: ">20ft floating Skagit head (short)"),
    ChecklistItem(title: "Short Spey rod 12-13.5ft", subtitle: "Floating Skagit head for tips")
  ]

  // MARK: - Body
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let errorText {
            Text(errorText)
              .foregroundColor(.red)
              .font(.footnote)
          }
          if let infoText {
            Text(infoText)
              .foregroundColor(.gray)
              .font(.footnote)
          }

          Text("The Oregon Coast offers diverse rivers each with unique character. The equipment below is tailored to the conditions you'll encounter.")
            .foregroundColor(.white)
            .font(.body)
            .italic()

          Text("Instructions: Please take a moment to check off what you plan to bring on the trip and answer one question")
            .foregroundColor(.white)
            .font(.subheadline)

          // Mandatory Section Header
          Text("Mandatory gear")
            .font(.headline.weight(.semibold))
            .foregroundColor(.blue)

          Text("These items are essential for you to bring to have a safe and comfortable trip")
            .foregroundColor(.white)
            .font(.subheadline)

          // Mandatory Section
          checklistSection(items: mandatoryItems, selections: $mandatorySelections, squareStyle: true)

          // Recommended Section Header
          Text("Recommended gear")
            .font(.headline.weight(.semibold))
            .foregroundColor(.blue)

          Text("Oregon Coast rivers vary from tidal estuaries to forested mountain streams. Match your rod selection to the water you'll be fishing.")
            .foregroundColor(.white)
            .font(.subheadline)

          // Recommended Section
          checklistSection(items: recommendedItems, selections: $recommendedSelections, squareStyle: true)

          // Reel hand question
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Image(systemName: "hand.raised")
                .foregroundColor(.blue)
                .font(.headline)
              Text("Which hand do you reel with?")
                .font(.headline)
                .italic()
                .foregroundColor(.blue)
            }
            Picker("Reel Hand", selection: $reelHand) {
              ForEach(ReelHand.allCases) { hand in
                Text(hand.label).tag(hand)
              }
            }
            .pickerStyle(.segmented)
            .tint(.blue)
            .accentColor(.blue)
            .onChange(of: reelHand) { _ in isDirty = true }
          }

          // Optional (collapsible)
          Button(action: { withAnimation { showOptional.toggle() } }) {
            HStack {
              Text("See optional gear")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.blue)
              Spacer()
              Image(systemName: showOptional ? "chevron.up" : "chevron.down")
                .foregroundColor(.white)
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .padding(.top, 8)

          if showOptional {
            VStack(alignment: .leading, spacing: 10) {
              Text("While the lodge carries spare rods, reels, flies and tippet for guests, some guest prefer to bring there own")
                .foregroundColor(.white)
                .font(.body)

              optionalSection()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }

          Spacer(minLength: 32)
        }
        .padding(.horizontal)
        .padding(.top)
      }
    }
    .navigationTitle("Gear checklist")
    .navigationBarTitleDisplayMode(.inline)
    .preferredColorScheme(.dark)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text("Gear checklist")
          .font(.headline.weight(.semibold))
          .foregroundColor(.white)
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          Task {
            isSaving = true
            errorText = nil
            let ok = await saveGear()
            isSaving = false
            if ok {
              isDirty = false
              infoText = "Saved"
            }
            saveSucceeded = ok
            showSaveAlert = true
          }
        } label: {
          HStack(spacing: 4) {
            if isSaving {
              ProgressView()
                .tint(.white)
            }
            Text("Save")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(isDirty && !isSaving ? Color.blue : Color.gray)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isDirty || isSaving)
      }
    }
    .alert(saveSucceeded ? "Saved" : "Save failed", isPresented: $showSaveAlert) {
      Button(action: { if saveSucceeded { dismiss() } }) { Text("OK").foregroundColor(.white) }
    } message: {
      if saveSucceeded {
        Text("Your gear checklist has been saved.")
      } else {
        Text(errorText ?? "We couldn't save your gear checklist. Please try again.")
      }
    }
    .tint(.blue)
    .task {
      await loadGear()
      syncBooleansFromSelections()
      isDirty = false
    }
  }

  // MARK: - Subviews
  private func checklistSection(items: [ChecklistItem], selections: Binding<Set<UUID>>, squareStyle: Bool = true) -> some View {
    VStack(spacing: 12) {
      ForEach(items) { item in
        HStack(alignment: .top, spacing: 12) {
          Button(action: {
            toggleSelection(id: item.id, selections: selections)
            isDirty = true
            syncBooleansFromSelections()
          }) {
            if squareStyle {
              let isOn = selections.wrappedValue.contains(item.id)
              ZStack {
                RoundedRectangle(cornerRadius: 2)
                  .stroke(Color.blue, lineWidth: 2)
                  .frame(width: 16, height: 16)
                if isOn {
                  Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .font(.system(size: 10, weight: .bold))
                }
              }
            } else {
              Image(systemName: selections.wrappedValue.contains(item.id) ? "checkmark.circle.fill" : "circle")
                .foregroundColor(selections.wrappedValue.contains(item.id) ? .green : .white.opacity(0.85))
                .font(.title3)
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
              .foregroundColor(.white)
              .font(.body)
            if let subtitle = item.subtitle {
              Text(subtitle)
                .foregroundColor(.gray)
                .font(.subheadline)
            }
          }
          Spacer()
        }
      }
    }
  }

  private func optionalSection() -> some View {
    VStack(alignment: .leading, spacing: 10) {
      bulletCategory("Rods:", bullets: [
        "Switch rod with short heads like OPST Commando or Skagit short for navigating creeks with overhanging brush and little backcast room",
        "Short spey rod with floating Skagit head for tips and longer casts with good line control"
      ])

      bulletCategory("Reels:", bullets: [
        "Drag reels preferred with good capacity and strong backing"
      ])

      bulletCategory("Spey Tips:", bullets: [
        "10 ft T mow tips (t14, t17)",
        "7.5 ft T/ 2.5 ft float mow tips (t 11, t14, t17)",
        "5 ft T/ 5 ft float mow tips (t 8, t11, t14)",
        "2.5 ft T/ 7.5 ft float mow tips (t11)",
        "Floating mow tip"
      ])

      Text("Flies:")
        .foregroundColor(Color.blue)
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 16)
      Text("Intruder and popsicle style flies best in pink, black and blue and egg sucking varieties. Many fly changes are common and expect to lose flies each day in overhead branches and bottom structure.")
        .foregroundColor(.white)
        .font(.body)
        .padding(.horizontal, 16)
      VStack(alignment: .leading, spacing: 8) {
        bullet("Fish taco black or pink")
        bullet("Weighted reverse marabou pink/white or black/blue")
        bullet("Silvinator orange bead")
        bullet("Silvey tandem tube")
        bullet("Stus ostrich intruder pink")
        bullet("Stus ostrich mini intruder pink and orange")
      }
      .padding(.horizontal, 16)

      bulletCategory("Leader Material:", bullets: [
        "20lbs maxima ultragreen"
      ])
    }
  }

  private func bulletCategory(_ title: String, bullets: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .foregroundColor(Color.blue)
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 16)
      VStack(alignment: .leading, spacing: 8) {
        ForEach(bullets, id: \.self) { b in
          bullet(b)
        }
      }
      .padding(.horizontal, 16)
    }
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(Color.white.opacity(0.85))
        .frame(width: 8, height: 8)
        .padding(.top, 6)
      Text(text)
        .foregroundColor(.white)
        .font(.body)
      Spacer()
    }
  }

  private func toggleSelection(id: UUID, selections: Binding<Set<UUID>>) {
    if selections.wrappedValue.contains(id) {
      selections.wrappedValue.remove(id)
    } else {
      selections.wrappedValue.insert(id)
    }
  }

  private func syncBooleansFromSelections() {
    hasWaders = mandatoryItems.contains { $0.title == "Waders" && mandatorySelections.contains($0.id) }
    hasBoots = mandatoryItems.contains { $0.title == "Boots" && mandatorySelections.contains($0.id) }
    hasWadingJacket = mandatoryItems.contains { $0.title == "Wading Jacket" && mandatorySelections.contains($0.id) }
    hasSwitchRod = recommendedItems.contains { $0.title.hasPrefix("Switch rod") && recommendedSelections.contains($0.id) }
    hasShortSpey = recommendedItems.contains {
      ($0.title.hasPrefix("Short Spey") || $0.title.hasPrefix("Short spey")) && recommendedSelections.contains($0.id)
    }
  }

  private func reflectBooleansIntoSelections() {
    mandatorySelections.removeAll()
    recommendedSelections.removeAll()
    if let waders = mandatoryItems.first(where: { $0.title == "Waders" }), hasWaders { mandatorySelections.insert(waders.id) }
    if let boots = mandatoryItems.first(where: { $0.title == "Boots" }), hasBoots { mandatorySelections.insert(boots.id) }
    if let jacket = mandatoryItems.first(where: { $0.title == "Wading Jacket" }), hasWadingJacket { mandatorySelections.insert(jacket.id) }
    if let switchRod = recommendedItems.first(where: { $0.title.hasPrefix("Switch rod") }), hasSwitchRod { recommendedSelections.insert(switchRod.id) }
    if let shortSpey = recommendedItems.first(where: { $0.title.hasPrefix("Short Spey") || $0.title.hasPrefix("Short spey") }), hasShortSpey { recommendedSelections.insert(shortSpey.id) }
  }

  private func loadFromCache(anglerId: String, lodgeName: String) {
    let key = cacheKey(anglerId: anglerId, lodgeName: lodgeName)
    if let dict = UserDefaults.standard.dictionary(forKey: key) {
      hasWaders = dict["waders"] as? Bool ?? false
      hasBoots = dict["boots"] as? Bool ?? false
      hasWadingJacket = dict["wading_jacket"] as? Bool ?? false
      hasSwitchRod = dict["switch_rod"] as? Bool ?? false
      hasShortSpey = dict["short_spey"] as? Bool ?? false
      if let rh = dict["reel_hand"] as? String, let parsed = ReelHand(rawValue: rh) { reelHand = parsed }
      reflectBooleansIntoSelections()
    }
  }

  private func loadGear() async {
    errorText = nil
    let lodgeName = "Bend Fly Shop"

    let tokenOpt = await auth.currentAccessToken()
    guard let token = tokenOpt, !token.isEmpty else {
      if let anglerId = auth.currentAnglerNumber {
        loadFromCache(anglerId: anglerId, lodgeName: lodgeName)
      }
      return
    }
    guard let anglerId = auth.currentAnglerNumber, !anglerId.isEmpty else { return }

    let url: URL
    do {
      url = try GearAPI.gearURL()
    } catch {
      errorText = error.localizedDescription
      loadFromCache(anglerId: anglerId, lodgeName: lodgeName)
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(AppEnvironment.shared.anonKey, forHTTPHeaderField: "apikey")

    AppLogging.log("Gear GET — URL: \(url.absoluteString)", level: .debug, category: .angler)

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      AppLogging.log("Gear GET — Status: \(code)", level: .debug, category: .angler)

      guard (200..<300).contains(code) else {
        loadFromCache(anglerId: anglerId, lodgeName: lodgeName)
        return
      }

      struct GearRecord: Decodable {
        let lodge_id: String?
        let waders: Bool?
        let boots: Bool?
        let wading_jacket: Bool?
        let switch_rod: Bool?
        let short_spey: Bool?
        let reel_hand: String?
        let lodges: LodgeObj?
        struct LodgeObj: Decodable { let id: String?; let name: String? }
      }

      let records = try JSONDecoder().decode([GearRecord].self, from: data)
      let preferred = records.first { ($0.lodges?.name ?? "").localizedCaseInsensitiveContains(lodgeName) } ?? records.first

      if let r = preferred {
        hasWaders = r.waders ?? false
        hasBoots = r.boots ?? false
        hasWadingJacket = r.wading_jacket ?? false
        hasSwitchRod = r.switch_rod ?? false
        hasShortSpey = r.short_spey ?? false
        if let rh = r.reel_hand, let parsed = ReelHand(rawValue: rh) { reelHand = parsed }

        reflectBooleansIntoSelections()

        let payload: [String: Any] = [
          "waders": hasWaders,
          "boots": hasBoots,
          "wading_jacket": hasWadingJacket,
          "switch_rod": hasSwitchRod,
          "short_spey": hasShortSpey,
          "reel_hand": reelHand.rawValue
        ]
        UserDefaults.standard.set(payload, forKey: cacheKey(anglerId: anglerId, lodgeName: lodgeName))
      } else {
        loadFromCache(anglerId: anglerId, lodgeName: lodgeName)
      }
    } catch {
      loadFromCache(anglerId: anglerId, lodgeName: lodgeName)
    }
  }

  private func saveGear() async -> Bool {
    let tokenOpt = await auth.currentAccessToken()
    guard let token = tokenOpt, !token.isEmpty else {
      errorText = "You are not signed in."
      return false
    }
    guard let anglerId = auth.currentAnglerNumber, !anglerId.isEmpty else {
      errorText = "Missing angler id."
      return false
    }

    struct GearBody: Encodable {
      let angler_id: String
      let lodge_name: String?
      let waders: Bool?
      let boots: Bool?
      let wading_jacket: Bool?
      let switch_rod: Bool?
      let short_spey: Bool?
      let reel_hand: String?
    }

    let url: URL
    do {
      url = try GearAPI.gearURL()
    } catch {
      errorText = error.localizedDescription
      return false
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(AppEnvironment.shared.anonKey, forHTTPHeaderField: "apikey")

    let body = GearBody(
      angler_id: anglerId,
      lodge_name: "Bend Fly Shop",
      waders: hasWaders,
      boots: hasBoots,
      wading_jacket: hasWadingJacket,
      switch_rod: hasSwitchRod,
      short_spey: hasShortSpey,
      reel_hand: reelHand.rawValue
    )

    AppLogging.log("Gear POST — URL: \(url.absoluteString)", level: .debug, category: .angler)

    do {
      req.httpBody = try JSONEncoder().encode(body)
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      AppLogging.log("Gear POST — Status: \(code)", level: .debug, category: .angler)

      guard (200..<300).contains(code) else {
        let msg = String(data: data, encoding: .utf8) ?? "Save failed."
        errorText = "Save failed (\(code)): \(msg)"
        return false
      }

      let key = cacheKey(anglerId: anglerId, lodgeName: "Bend Fly Shop")
      let payload: [String: Any] = [
        "waders": hasWaders,
        "boots": hasBoots,
        "wading_jacket": hasWadingJacket,
        "switch_rod": hasSwitchRod,
        "short_spey": hasShortSpey,
        "reel_hand": reelHand.rawValue
      ]
      UserDefaults.standard.set(payload, forKey: key)

      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }
}

private struct ChecklistItem: Identifiable, Hashable {
  let id = UUID()
  let title: String
  let subtitle: String?
}

#Preview {
  NavigationView {
    GearChecklist()
  }
}
