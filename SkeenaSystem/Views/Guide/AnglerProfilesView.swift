import SwiftUI
import Foundation
import Combine

private struct TripRosterResponse: Decodable {
  let trips: [TripDTO]
}
private struct TripDTO: Decodable, Identifiable {
  let trip_id: String
  let trip_name: String?
  let start_date: String
  let end_date: String
  let anglers: [AnglerDTO]
  var id: String { trip_id }
}
private struct AnglerDTO: Decodable, Identifiable, Hashable, Equatable {
  let angler_id: String
  let last_name: String
  let first_name: String
  let angler_number: String
  var id: String { angler_id }
}

extension AnglerDTO {
  static func == (lhs: AnglerDTO, rhs: AnglerDTO) -> Bool { lhs.angler_id == rhs.angler_id }
  func hash(into hasher: inout Hasher) { hasher.combine(angler_id) }
}

private struct PreferencesDTO: Decodable {
  let drinks: Bool?
  let drinks_text: String?
  let food: Bool?
  let food_text: String?
  let health: Bool?
  let health_text: String?
  let occasion: Bool?
  let occasion_text: String?
  let allergies: Bool?
  let allergies_text: String?
  let cpap: Bool?
  let cpap_text: String?
}
private struct ProficiencyDTO: Decodable {
  let casting: Int?
  let wading: Int?
  let hiking: Int?
  let learning_style: Int?
  let lodge_name: String?
  let species_name: String?
  let tactic_name: String?
}
private struct GearDTO: Decodable {
  let lodge_name: String?
  let waders: Bool?
  let boots: Bool?
  let wading_jacket: Bool?
  let switch_rod: Bool?
  let short_spey: Bool?
  let reel_hand: String?
}

// New detailed DTOs for Angler Details API
private struct AnglerDetailsResponse: Decodable {
  let angler_id: String
  let angler_number: String
  let first_name: String
  let last_name: String
  let preferences: PreferencesDTO?
  let proficiencies: [ProficiencyDetailsDTO]?
  let gear: [GearDTO]?
}
private struct ProficiencyDetailsDTO: Decodable {
  let casting: Int?
  let wading: Int?
  let hiking: Int?
  let learning_style: Int?
  let lodge_name: String?
  let species_name: String?
  let tactic_name: String?
  let casting_context: ProficiencyContextDTO?
  let wading_context: ProficiencyContextDTO?
  let hiking_context: ProficiencyContextDTO?
  let learning_style_context: ProficiencyContextDTO?
}
private struct ProficiencyContextDTO: Decodable {
  let question: String?
  let context: String?
  let high: String?
  let medium: String?
  let low: String?
}

private enum TripRosterAPI {
  // Composable base + path URLs from Info.plist keys, fallback defaults

  private static let rawBaseURLString = APIURLUtilities.infoPlistString(forKey: "API_BASE_URL")
  private static let baseURLString = APIURLUtilities.normalizeBaseURL(rawBaseURLString)
  private static let tripRosterPath: String = {
    let path = APIURLUtilities.infoPlistString(forKey: "TRIP_ROSTER_PATH")
    return path.isEmpty ? "/functions/v1/trip-roster" : path
  }()
  private static let anglerDetailsPath: String = {
    let path = APIURLUtilities.infoPlistString(forKey: "ANGLER_DETAILS_PATH")
    return path.isEmpty ? "/functions/v1/angler-details" : path
  }()
  private static let apiKey = APIURLUtilities.infoPlistString(forKey: "API_KEY")

  private static func logConfig() {
    AppLogging.log("TripRosterAPI config — API_BASE_URL (raw): '" + rawBaseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — API_BASE_URL (normalized): '" + baseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — roster path: '" + tripRosterPath + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — details path: '" + anglerDetailsPath + "'", level: .debug, category: .trip)
  }

  private static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("TripRosterAPI invalid API_BASE_URL — raw: '" + rawBaseURLString + "', normalized: '" + baseURLString + "'", level: .debug, category: .trip)
      throw NSError(domain: "TripRoster", code: -1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API_BASE_URL (raw: '" + rawBaseURLString + "', normalized: '" + baseURLString + "')"])
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
      throw NSError(domain: "TripRoster", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Failed to build URL for path: \(path)"])
    }
    return url
  }

  static func fetchRoster(community: String, lodge: String) async throws -> TripRosterResponse {
    logConfig()
    let url = try makeURL(path: tripRosterPath, queryItems: [
      URLQueryItem(name: "community", value: community),
      URLQueryItem(name: "lodge", value: lodge)
    ])
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "apikey") }
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    AppLogging.log("TripRosterAPI request URL: \(url.absoluteString)", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI headers — apikey prefix: \(apiKey.prefix(8))…, Accept: application/json", level: .debug, category: .trip)

    AppLogging.log("Fetching trip roster with URL: \(req.url?.absoluteString ?? "nil")", level: .debug, category: .trip)
    AppLogging.log("HTTP Method: \(req.httpMethod ?? "nil")", level: .debug, category: .trip)
    AppLogging.log("Headers: apikey: \(apiKey.prefix(8))…, Accept: application/json", level: .debug, category: .trip)

    let (data, resp) = try await URLSession.shared.data(for: req)

    let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
    let previewData = data.prefix(512)
    let previewString = String(data: previewData, encoding: .utf8) ?? "<non-UTF8 data>"

    AppLogging.log("Received response status: \(statusCode), body preview: \(previewString)", level: .debug, category: .trip)

    guard let http = resp as? HTTPURLResponse else {
      throw NSError(domain: "TripRoster", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
    }
    guard (200...299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      AppLogging.log("TripRosterAPI request failed with status \(http.statusCode), body: \(body)", level: .debug, category: .trip)
      throw NSError(domain: "TripRoster", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "HTTP \(http.statusCode)" : body])
    }

    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .useDefaultKeys
    return try dec.decode(TripRosterResponse.self, from: data)
  }

  static func fetchAnglerDetails(anglerID: String, community: String, lodge: String) async throws -> AnglerDetailsResponse {
    logConfig()
    let url = try makeURL(path: anglerDetailsPath, queryItems: [
      URLQueryItem(name: "angler_id", value: anglerID),
      URLQueryItem(name: "community", value: community),
      URLQueryItem(name: "lodge", value: lodge)
    ])
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "apikey") }
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    AppLogging.log("AnglerDetails request URL: \(url.absoluteString)", level: .debug, category: .trip)
    AppLogging.log("AnglerDetails headers — apikey prefix: \(apiKey.prefix(8))…, Accept: application/json", level: .debug, category: .trip)

    AppLogging.log("Fetching angler details with URL: \(req.url?.absoluteString ?? "nil")", level: .debug, category: .trip)

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(domain: "AnglerDetails", code: status, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "HTTP \(status)" : body])
    }
    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .useDefaultKeys
    return try dec.decode(AnglerDetailsResponse.self, from: data)
  }
}

@MainActor
private final class AnglerProfilesVM: ObservableObject {
  @Published var isLoading = false
  @Published var error: String?
  @Published var anglers: [AnglerDTO] = []

  let community: String
  let lodge: String

  init(community: String, lodge: String) {
    self.community = community
    self.lodge = lodge
  }

  func load() async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let resp = try await TripRosterAPI.fetchRoster(community: community, lodge: lodge)
      // Flatten anglers across trips
      var set = Set<AnglerDTO>()
      for t in resp.trips { for a in t.anglers { set.insert(a) } }
      // Sort by last name, then first name
      self.anglers = set.sorted { lhs, rhs in
        let lLast = lhs.last_name.lowercased(); let rLast = rhs.last_name.lowercased()
        if lLast == rLast { return lhs.first_name.lowercased() < rhs.first_name.lowercased() }
        return lLast < rLast
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}

struct AnglerProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AnglerProfilesVM(community: AppEnvironment.shared.communityName, lodge: "Bend Fly Shop")

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading…")
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error {
                Text(err)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.anglers.isEmpty {
                Text("No anglers found.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.anglers, id: \.id) { a in
                    NavigationLink(destination: AnglerDetailsSheetView(anglerID: a.angler_id, displayName: "\(a.first_name) \(a.last_name)", anglerNumber: a.angler_number, community: vm.community, lodge: vm.lodge)) {
                        Text("\(a.last_name), \(a.first_name)")
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.black)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Anglers")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .foregroundColor(.white)
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            await vm.load()
        }
}

}

// MARK: - New Detail View and VM for Angler Details

@MainActor
private final class AnglerDetailsVM: ObservableObject {
  @Published var isLoading = false
  @Published var error: String?
  @Published var details: AnglerDetailsResponse?

  let anglerID: String
  let community: String
  let lodge: String

  init(anglerID: String, community: String, lodge: String) {
    self.anglerID = anglerID
    self.community = community
    self.lodge = lodge
  }

  func load() async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let resp = try await TripRosterAPI.fetchAnglerDetails(anglerID: anglerID, community: community, lodge: lodge)
      self.details = resp
    } catch {
      self.error = error.localizedDescription
    }
  }
}

private struct AnglerDetailsSheetView: View {
  let anglerID: String
  let displayName: String
  let anglerNumber: String
  let community: String
  let lodge: String

  @StateObject private var vm: AnglerDetailsVM

  init(anglerID: String, displayName: String, anglerNumber: String, community: String, lodge: String) {
    self.anglerID = anglerID
    self.displayName = displayName
    self.anglerNumber = anglerNumber
    self.community = community
    self.lodge = lodge
    _vm = StateObject(wrappedValue: AnglerDetailsVM(anglerID: anglerID, community: community, lodge: lodge))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Removed the entire header VStack with displayName as per instructions

        if vm.isLoading {
          VStack {
            Spacer(minLength: 80)
            HStack {
              Spacer()
              ProgressView("Loading…")
                .tint(.white)
              Spacer()
            }
            Spacer(minLength: 80)
          }
          .frame(maxWidth: .infinity)
        } else if let err = vm.error {
          Text(err)
            .foregroundColor(.red)
        } else if let details = vm.details {

          // Learning style sentence above proficiencies
          if let profs = details.proficiencies, !profs.isEmpty, let sentence = learningStyleSentence(firstName: details.first_name, profs: profs) {
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline, spacing: 4) {
                let parts = sentence.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                Text("Learning style:")
                  .foregroundColor(.blue)
                  .font(.subheadline)
                if parts.count == 2 {
                  Text(String(parts[1]).trimmingCharacters(in: .whitespaces))
                    .foregroundColor(.white)
                    .font(.subheadline)
                } else {
                  Text(sentence)
                    .foregroundColor(.white)
                    .font(.subheadline)
                }
              }
            }
            .padding(.bottom, 12)
          }

          SelfAssessmentSection(profs: details.proficiencies)

          PreferencesSection(preferences: details.preferences, profs: details.proficiencies)

          GearSection(gearList: details.gear, firstName: details.first_name)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.black)
    }
    .navigationTitle(displayName)
    .navigationBarTitleDisplayMode(.inline)
    .preferredColorScheme(.dark)
    .task { await vm.load() }
  }
}

// MARK: - Helpers used by AnglerDetailsSheetView

private func proficiencySummaryRowFromDetails(_ prof: ProficiencyDetailsDTO) -> some View {
  VStack(alignment: .leading, spacing: 8) {
    HStack {
      meter(label: "Casting", value: prof.casting, kind: .skill)
      Spacer()
      meter(label: "Wading", value: prof.wading, kind: .skill)
      Spacer()
      meter(label: "Hiking", value: prof.hiking, kind: .skill)
      Spacer()
      meter(label: "Learning", value: prof.learning_style, kind: .learning)
    }
    .frame(maxWidth: .infinity)
  }
}

private func proficiencyQuestionMeterRow(_ prof: ProficiencyDetailsDTO) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    // Casting
    if let question = prof.casting_context?.question {
      HStack(alignment: .center) {
        Text(question)
          .foregroundColor(.white)
          .font(.subheadline)
          .frame(maxWidth: .infinity, alignment: .leading)
        meter(label: "", value: prof.casting, kind: .skill)
      }
    }
    // Wading
    if let question = prof.wading_context?.question {
      HStack(alignment: .center) {
        Text(question)
          .foregroundColor(.white)
          .font(.subheadline)
          .frame(maxWidth: .infinity, alignment: .leading)
        meter(label: "", value: prof.wading, kind: .skill)
      }
    }
    // Hiking
    if let question = prof.hiking_context?.question {
      HStack(alignment: .center) {
        Text(question)
          .foregroundColor(.white)
          .font(.subheadline)
          .frame(maxWidth: .infinity, alignment: .leading)
        meter(label: "", value: prof.hiking, kind: .skill)
      }
    }
  }
}

private func learningStyleSentence(firstName: String, profs: [ProficiencyDetailsDTO]) -> String? {
  guard let style = profs.compactMap({ $0.learning_style }).first,
        let ctx = profs.compactMap({ $0.learning_style_context }).first else { return nil }
  // Derive a simple level adjective (low/medium/high) from the context, lowercased
  let adjective: String
  if style < 34 { adjective = (ctx.low ?? "low").components(separatedBy: ",").first?.lowercased() ?? "low" } else if style < 66 { adjective = (ctx.medium ?? "medium").components(separatedBy: ",").first?.lowercased() ?? "medium" } else { adjective = (ctx.high ?? "high").components(separatedBy: ",").first?.lowercased() ?? "high" }
  return "Learning style: \(firstName) prefers \(adjective) instruction"
}

private struct PreferencesSection: View {
  let preferences: PreferencesDTO?
  let profs: [ProficiencyDetailsDTO]?
  @State private var show: Bool = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: { withAnimation { show.toggle() } }) {
        HStack {
          Image(systemName: show ? "chevron.down" : "chevron.right").foregroundColor(.blue)
          Text("Preferences").font(.headline).foregroundColor(.blue).fontWeight(.semibold)
          Spacer()
        }
        .padding(.vertical, 4)
      }
      if show {
        if let prefs = preferences {
          VStack(alignment: .leading, spacing: 6) {
            // Compute which preferences are true
            let anyYes = [
              prefs.drinks == true,
              prefs.food == true,
              prefs.health == true,
              prefs.occasion == true,
              prefs.allergies == true,
              prefs.cpap == true
            ].contains(true)

            // Rows (they only render when true via preferenceRow helper)
            preferenceRow(label: "Drinks", value: prefs.drinks, text: prefs.drinks_text)
            preferenceRow(label: "Food", value: prefs.food, text: prefs.food_text)
            preferenceRow(label: "Health", value: prefs.health, text: prefs.health_text)
            preferenceRow(label: "Occasion", value: prefs.occasion, text: prefs.occasion_text)
            preferenceRow(label: "Allergies", value: prefs.allergies, text: prefs.allergies_text)
            preferenceRow(label: "CPAP", value: prefs.cpap, text: prefs.cpap_text)

            // Footer message depending on presence of any 'yes'
            if anyYes {
              Text("No additional preferences indicated")
                .font(.subheadline)
                .foregroundColor(.white)
                .italic()
                .padding(.top, 6)
            } else {
              Text("No preferences indicated")
                .font(.subheadline)
                .foregroundColor(.white)
                .italic()
                .padding(.top, 6)
            }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
          Text("No preferences provided.").foregroundColor(.gray).padding(.leading, 4).transition(.opacity)
        }
      }
    }
  }
}

// Added SelfAssessmentSection as per instructions
private struct SelfAssessmentSection: View {
  let profs: [ProficiencyDetailsDTO]?
  @State private var show: Bool = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: { withAnimation { show.toggle() } }) {
        HStack {
          Image(systemName: show ? "chevron.down" : "chevron.right").foregroundColor(.blue)
          Text("Self-assessment").font(.headline).foregroundColor(.blue).fontWeight(.semibold)
          Spacer()
        }
        .padding(.vertical, 4)
      }
      if show {
        if let profs = profs, !profs.isEmpty {
          let tactic = profs.compactMap { $0.tactic_name?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
          let species = profs.compactMap { $0.species_name?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
          if tactic != nil || species != nil {
            HStack(spacing: 8) {
              if let tactic = tactic { chip(tactic) }
              if let species = species { chip(species) }
              Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
          }
          VStack(alignment: .leading, spacing: 12) {
            ForEach(profs.indices, id: \.self) { idx in
              proficiencyQuestionMeterRow(profs[idx])
              if idx < profs.count - 1 {
                Divider().background(Color.white.opacity(0.2))
              }
            }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
          Text("No proficiencies recorded.")
            .foregroundColor(.gray)
            .padding(.leading, 4)
            .transition(.opacity)
        }
      }
    }
  }
}

// Updated GearSection to include firstName and new UI logic
private struct GearSection: View {
  let gearList: [GearDTO]?
  let firstName: String
  @State private var show: Bool = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: { withAnimation { show.toggle() } }) {
        HStack {
          Image(systemName: show ? "chevron.down" : "chevron.right").foregroundColor(.blue)
          Text("Gear").font(.headline).foregroundColor(.blue).fontWeight(.semibold)
          Spacer()
        }
        .padding(.vertical, 4)
      }
      if show {
        if let gearList = gearList, !gearList.isEmpty {
          let reel = gearList.compactMap { $0.reel_hand?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
          let reelDisplay = (reel?.isEmpty == false ? reel!.lowercased() : "—")
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text("Reel hand:").foregroundColor(.blue).font(.subheadline)
              Text("\(firstName) reels \(reelDisplay)-handed").foregroundColor(.white).font(.subheadline)
            }
            ForEach(gearList.indices, id: \.self) { idx in
              gearRow(gearList[idx], firstName: firstName)
              if idx < gearList.count - 1 {
                Divider().background(Color.white.opacity(0.2))
              }
            }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
          Text("No gear recorded.").foregroundColor(.gray).padding(.leading, 4).transition(.opacity)
        }
      }
    }
  }
}

// MARK: - Reused helpers from original detail view

private func sectionHeader(_ title: String) -> some View {
  Text(title)
    .font(.headline)
    .foregroundColor(Color.blue)
    .fontWeight(.semibold)
    .padding(.vertical, 4)
}

@ViewBuilder
private func preferenceRow(label: String, value: Bool?, text: String?) -> some View {
  if let val = value, val == true {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(label)
          .font(.subheadline)
          .foregroundColor(.blue)
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(t)
            .font(.subheadline)
            .foregroundColor(.white)
        }
      }
    }
  } else {
    EmptyView()
  }
}

private enum MeterKind { case skill, learning }
private func meter(label: String, value: Int?, kind: MeterKind) -> some View {
  VStack(spacing: 6) {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.15), lineWidth: 8)
        .frame(width: 54, height: 54)
      if let v = value {
        let clamped = max(0, min(v, 100))
        let color: Color = {
          switch kind {
          case .learning:
            return .white
          case .skill:
            if clamped <= 33 { return .red } else if clamped <= 75 { return .yellow } else { return .green }
          }
        }()
        Circle()
          .trim(from: 0, to: CGFloat(clamped) / 100.0)
          .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .frame(width: 54, height: 54)
        Text("\(clamped)")
          .font(.caption)
          .foregroundColor(.white)
      } else {
        Text("–")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    Text(label)
      .font(.caption2)
      .foregroundColor(.white)
  }
}

// Updated chip function styling as per instructions
private func chip(_ text: String) -> some View {
  Text(text)
    .font(.caption)
    .foregroundColor(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(
      Capsule()
        .fill(Color.blue.opacity(0.35))
    )
}

// Updated gearRow signature and implementation
private func gearRow(_ gear: GearDTO, firstName: String) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    // Removed lodge_name entirely per instructions

    VStack(alignment: .leading, spacing: 2) {
      if let waders = gear.waders {
        HStack {
          Text("Waders")
            .foregroundColor(.blue)
            .font(.subheadline)
          Spacer()
          Image(systemName: waders ? "checkmark.square" : "square")
            .foregroundColor(.white)
        }
      }
      if let boots = gear.boots {
        HStack {
          Text("Boots")
            .foregroundColor(.blue)
            .font(.subheadline)
          Spacer()
          Image(systemName: boots ? "checkmark.square" : "square")
            .foregroundColor(.white)
        }
      }
      if let jacket = gear.wading_jacket {
        HStack {
          Text("Wading Jacket")
            .foregroundColor(.blue)
            .font(.subheadline)
          Spacer()
          Image(systemName: jacket ? "checkmark.square" : "square")
            .foregroundColor(.white)
        }
      }
      if let switchRod = gear.switch_rod {
        HStack {
          Text("Switch Rod")
            .foregroundColor(.blue)
            .font(.subheadline)
          Spacer()
          Image(systemName: switchRod ? "checkmark.square" : "square")
            .foregroundColor(.white)
        }
      }
      if let shortSpey = gear.short_spey {
        HStack {
          Text("Short Spey")
            .foregroundColor(.blue)
            .font(.subheadline)
          Spacer()
          Image(systemName: shortSpey ? "checkmark.square" : "square")
            .foregroundColor(.white)
        }
      }
    }
  }
}

// Removed gearBoolRow(label:value:) helper as per instructions

#if DEBUG
struct AnglerProfilesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AnglerProfilesView()
        }
    }
}
#endif
