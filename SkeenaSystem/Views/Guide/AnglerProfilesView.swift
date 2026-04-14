import SwiftUI
import Foundation
import Combine

struct RosterTripResponse: Decodable {
  let trips: [RosterTripDTO]
}
struct RosterTripDTO: Decodable, Identifiable {
  let trip_id: String
  let trip_name: String?
  let start_date: String
  let end_date: String
  let anglers: [RosterAnglerDTO]
  var id: String { trip_id }
}
struct RosterAnglerDTO: Decodable, Identifiable, Hashable, Equatable {
  let member_id: String
  let last_name: String
  let first_name: String
  let member_number: String
  var id: String { member_id }
}

extension RosterAnglerDTO {
  static func == (lhs: RosterAnglerDTO, rhs: RosterAnglerDTO) -> Bool { lhs.member_id == rhs.member_id }
  func hash(into hasher: inout Hasher) { hasher.combine(member_id) }
}

// MARK: - Generic field object from member-details API
//
// The member-details endpoint returns preferences, proficiencies, and gear
// as arrays of self-describing field objects. This struct decodes that format,
// and AnglerDetailsResponse maps them to the legacy flat DTOs so the display
// views don't need to change.

struct MemberField: Decodable {
  let field_name: String
  let field_label: String?
  let field_type: String?          // "boolean" | "number"
  let question_text: String?
  let context_text: String?
  let options: MemberFieldOptions?
  let value: String?
}

struct MemberFieldOptions: Decodable {
  let has_details: Bool?
  let details_prompt: String?
  let low: String?
  let medium: String?
  let high: String?
  let priority: String?

  // Accept any unknown keys gracefully
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    has_details = try container.decodeIfPresent(Bool.self, forKey: .has_details)
    details_prompt = try container.decodeIfPresent(String.self, forKey: .details_prompt)
    low = try container.decodeIfPresent(String.self, forKey: .low)
    medium = try container.decodeIfPresent(String.self, forKey: .medium)
    high = try container.decodeIfPresent(String.self, forKey: .high)
    priority = try container.decodeIfPresent(String.self, forKey: .priority)
  }
  enum CodingKeys: String, CodingKey {
    case has_details, details_prompt, low, medium, high, priority
  }
}

// MARK: - Legacy DTOs (used by display views)

struct PreferencesDTO {
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

  /// Build from an array of MemberField objects.
  init(fields: [MemberField]) {
    let map = Dictionary(uniqueKeysWithValues: fields.map { ($0.field_name, $0.value ?? "") })
    func parse(_ key: String) -> (Bool?, String?) {
      guard let raw = map[key] else { return (nil, nil) }
      if raw.hasPrefix("true") {
        let parts = raw.split(separator: "|", maxSplits: 1)
        let text = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (true, text)
      }
      return (raw == "false" ? false : nil, nil)
    }
    (drinks, drinks_text) = parse("drinks")
    (food, food_text) = parse("food")
    (health, health_text) = parse("health")
    (occasion, occasion_text) = parse("occasion")
    (allergies, allergies_text) = parse("allergies")
    (cpap, cpap_text) = parse("cpap")
  }
}

struct ProficiencyDTO: Decodable {
  let casting: Int?
  let wading: Int?
  let hiking: Int?
  let learning_style: Int?
  let lodge_name: String?
  let species_name: String?
  let tactic_name: String?
}

struct ProficiencyContextDTO {
  let question: String?
  let context: String?
  let high: String?
  let medium: String?
  let low: String?
}

struct ProficiencyDetailsDTO {
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

  /// Build from an array of MemberField objects.
  init(fields: [MemberField]) {
    func intVal(_ name: String) -> Int? {
      fields.first(where: { $0.field_name == name }).flatMap { Int($0.value ?? "") }
    }
    func ctx(_ name: String) -> ProficiencyContextDTO? {
      guard let f = fields.first(where: { $0.field_name == name }) else { return nil }
      return ProficiencyContextDTO(
        question: f.question_text,
        context: f.context_text,
        high: f.options?.high,
        medium: f.options?.medium,
        low: f.options?.low
      )
    }
    casting = intVal("casting")
    wading = intVal("wading")
    hiking = intVal("hiking")
    learning_style = intVal("learning_style")
    casting_context = ctx("casting")
    wading_context = ctx("wading")
    hiking_context = ctx("hiking")
    learning_style_context = ctx("learning_style")
    lodge_name = nil
    species_name = nil
    tactic_name = nil
  }
}

struct GearDTO {
  let lodge_name: String?
  let waders: Bool?
  let boots: Bool?
  let wading_jacket: Bool?
  let switch_rod: Bool?
  let short_spey: Bool?
  let reel_hand: String?

  /// Build from a single MemberField — one DTO per field.
  /// The display view iterates GearDTO[], so we collapse all fields into one.
  init(fields: [MemberField]) {
    func boolVal(_ name: String) -> Bool? {
      fields.first(where: { $0.field_name == name }).map { ($0.value ?? "") == "true" }
    }
    waders = boolVal("waders")
    boots = boolVal("boots")
    wading_jacket = boolVal("wading_jacket")
    switch_rod = boolVal("switch_rod")
    short_spey = boolVal("short_spey")
    reel_hand = nil  // not returned as a separate field in the new format
    lodge_name = nil
  }
}

// MARK: - Response DTO with custom decoder

struct AnglerDetailsResponse: Decodable {
  let member_id: String
  let member_number: String
  let first_name: String
  let last_name: String
  let preferences: PreferencesDTO?
  let proficiencies: [ProficiencyDetailsDTO]?
  let gear: [GearDTO]?

  enum CodingKeys: String, CodingKey {
    case member_id, member_number, first_name, last_name
    case preferences, proficiencies, gear
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    member_id = try c.decode(String.self, forKey: .member_id)
    member_number = try c.decodeIfPresent(String.self, forKey: .member_number) ?? ""
    first_name = try c.decodeIfPresent(String.self, forKey: .first_name) ?? ""
    last_name = try c.decodeIfPresent(String.self, forKey: .last_name) ?? ""

    // Preferences — array of MemberField → single PreferencesDTO
    if let prefFields = try? c.decode([MemberField].self, forKey: .preferences) {
      preferences = PreferencesDTO(fields: prefFields)
    } else {
      preferences = nil
    }

    // Proficiencies — array of MemberField → single ProficiencyDetailsDTO
    if let profFields = try? c.decode([MemberField].self, forKey: .proficiencies), !profFields.isEmpty {
      proficiencies = [ProficiencyDetailsDTO(fields: profFields)]
    } else {
      proficiencies = nil
    }

    // Gear — array of MemberField → single GearDTO with all fields
    if let gearFields = try? c.decode([MemberField].self, forKey: .gear), !gearFields.isEmpty {
      gear = [GearDTO(fields: gearFields)]
    } else {
      gear = nil
    }
  }
}

enum TripRosterAPI {
  // Composable base + path URLs from Info.plist keys, fallback defaults

  private static let rawBaseURLString = APIURLUtilities.infoPlistString(forKey: "API_BASE_URL")
  private static let baseURLString = APIURLUtilities.normalizeBaseURL(rawBaseURLString)
  private static let tripRosterPath: String = {
    let path = APIURLUtilities.infoPlistString(forKey: "TRIP_ROSTER_PATH")
    return path.isEmpty ? "/functions/v1/trip-roster" : path
  }()
  private static let memberDetailsPath: String = {
    let path = APIURLUtilities.infoPlistString(forKey: "MEMBER_DETAILS_PATH")
    return path.isEmpty ? "/functions/v1/member-details" : path
  }()
  private static let apiKey = APIURLUtilities.infoPlistString(forKey: "API_KEY")

  private static func logConfig() {
    AppLogging.log("TripRosterAPI config — API_BASE_URL (raw): '" + rawBaseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — API_BASE_URL (normalized): '" + baseURLString + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — roster path: '" + tripRosterPath + "'", level: .debug, category: .trip)
    AppLogging.log("TripRosterAPI config — details path: '" + memberDetailsPath + "'", level: .debug, category: .trip)
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

  static func fetchRoster(community: String, lodge: String) async throws -> RosterTripResponse {
    logConfig()
    var items: [URLQueryItem] = []
    if let communityId = CommunityService.shared.activeCommunityId {
      items.append(URLQueryItem(name: "community_id", value: communityId))
    }
    items.append(URLQueryItem(name: "lodge", value: lodge))
    let url = try makeURL(path: tripRosterPath, queryItems: items)
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
      AppLogging.log("TripRosterAPI request failed with status \(http.statusCode), body: \(body)", level: .error, category: .trip)
      throw NSError(domain: "TripRoster", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "HTTP \(http.statusCode)" : body])
    }

    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .useDefaultKeys
    return try dec.decode(RosterTripResponse.self, from: data)
  }

  /// Fetches member details via the `member-details` edge function.
  /// Accepts the member's UUID (the endpoint also accepts legacy angler_id).
  static func fetchMemberDetails(memberID: String) async throws -> AnglerDetailsResponse {
    logConfig()
    var items: [URLQueryItem] = [URLQueryItem(name: "member_id", value: memberID)]
    if let communityId = CommunityService.shared.activeCommunityId {
      items.append(URLQueryItem(name: "community_id", value: communityId))
    }
    let url = try makeURL(path: memberDetailsPath, queryItems: items)
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    if let token = await AuthService.shared.currentAccessToken(), !token.isEmpty {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "apikey") }
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    AppLogging.log("MemberDetails request URL: \(url.absoluteString)", level: .debug, category: .trip)

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
      let body = String(data: data, encoding: .utf8) ?? ""
      AppLogging.log("MemberDetails failed (\(status)): \(body)", level: .error, category: .trip)
      throw NSError(domain: "MemberDetails", code: status, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "HTTP \(status)" : body])
    }
    let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
    AppLogging.log("MemberDetails raw response: \(rawBody)", level: .debug, category: .trip)
    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .useDefaultKeys
    return try dec.decode(AnglerDetailsResponse.self, from: data)
  }
}

@MainActor
final class AnglerProfilesVM: ObservableObject {
  @Published var isLoading = false
  @Published var error: String?
  @Published var anglers: [RosterAnglerDTO] = []

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
      var set = Set<RosterAnglerDTO>()
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
    @StateObject private var vm = AnglerProfilesVM(community: CommunityService.shared.activeCommunityName, lodge: CommunityService.shared.activeCommunityName)

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
                    NavigationLink(destination: AnglerDetailsSheetView(memberID: a.member_id, displayName: "\(a.first_name) \(a.last_name)", memberNumber: a.member_number)) {
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
                    Image(systemName: "chevron.backward")
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
final class AnglerDetailsVM: ObservableObject {
  @Published var isLoading = false
  @Published var error: String?
  @Published var details: AnglerDetailsResponse?

  let memberID: String

  init(memberID: String) {
    self.memberID = memberID
  }

  func load() async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let resp = try await TripRosterAPI.fetchMemberDetails(memberID: memberID)
      self.details = resp
    } catch {
      AppLogging.log("MemberDetails decode/load error: \(error)", level: .error, category: .trip)
      self.error = error.localizedDescription
    }
  }
}

struct AnglerDetailsSheetView: View {
  let memberID: String
  let displayName: String
  let memberNumber: String

  @StateObject private var vm: AnglerDetailsVM

  init(memberID: String, displayName: String, memberNumber: String) {
    self.memberID = memberID
    self.displayName = displayName
    self.memberNumber = memberNumber
    _vm = StateObject(wrappedValue: AnglerDetailsVM(memberID: memberID))
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

          AnglerProfileGearSection(gearList: details.gear, firstName: details.first_name)
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

func proficiencySummaryRowFromDetails(_ prof: ProficiencyDetailsDTO) -> some View {
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

func proficiencyQuestionMeterRow(_ prof: ProficiencyDetailsDTO) -> some View {
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

func learningStyleSentence(firstName: String, profs: [ProficiencyDetailsDTO]) -> String? {
  guard let style = profs.compactMap({ $0.learning_style }).first,
        let ctx = profs.compactMap({ $0.learning_style_context }).first else { return nil }
  // Derive a simple level adjective (low/medium/high) from the context, lowercased
  let adjective: String
  if style < 34 { adjective = (ctx.low ?? "low").components(separatedBy: ",").first?.lowercased() ?? "low" } else if style < 66 { adjective = (ctx.medium ?? "medium").components(separatedBy: ",").first?.lowercased() ?? "medium" } else { adjective = (ctx.high ?? "high").components(separatedBy: ",").first?.lowercased() ?? "high" }
  return "Learning style: \(firstName) prefers \(adjective) instruction"
}

struct PreferencesSection: View {
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
struct SelfAssessmentSection: View {
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

// Updated AnglerProfileGearSection to include firstName and new UI logic
struct AnglerProfileGearSection: View {
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

func sectionHeader(_ title: String) -> some View {
  Text(title)
    .font(.headline)
    .foregroundColor(Color.blue)
    .fontWeight(.semibold)
    .padding(.vertical, 4)
}

@ViewBuilder
func preferenceRow(label: String, value: Bool?, text: String?) -> some View {
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

enum MeterKind { case skill, learning }
func meter(label: String, value: Int?, kind: MeterKind) -> some View {
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
func chip(_ text: String) -> some View {
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
func gearRow(_ gear: GearDTO, firstName: String) -> some View {
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
