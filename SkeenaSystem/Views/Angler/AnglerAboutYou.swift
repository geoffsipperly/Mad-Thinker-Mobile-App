// Bend Fly Shop
// AnglerAboutYou.swift

import SwiftUI
import Foundation

private struct AnglerContextResponse: Decodable {
  let contexts: [AnglerContext]
}

private struct AnglerContext: Decodable {
  let id: String
  let community: String?
  let learning_style_question: String?
  let learning_style_context: String?
  let learning_style_low: String?
  let learning_style_medium: String?
  let learning_style_high: String?
  let casting_question: String?
  let casting_context: String?
  let casting_low: String?
  let casting_medium: String?
  let casting_high: String?
  // Backward compatibility (mobility/gear) and new categories
  let mobility_question: String?
  let mobility_context: String?
  let mobility_low: String?
  let mobility_medium: String?
  let mobility_high: String?
  let wading_question: String?
  let wading_context: String?
  let wading_low: String?
  let wading_medium: String?
  let wading_high: String?
  let hiking_question: String?
  let hiking_context: String?
  let hiking_low: String?
  let hiking_medium: String?
  let hiking_high: String?
  let gear_question: String?
  let gear_context: String?
  let gear_low: String?
  let gear_medium: String?
  let gear_high: String?
  let species: NamedEntity?
  let tactics: NamedEntity?
  let lodges: NamedEntity?

  struct NamedEntity: Decodable { let id: String; let name: String }
}

// MARK: - URL composition (mirrors other files)

private enum AnglerAboutYouAPI {
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

  private static let proficiencyPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "PROFICIENCY_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/proficiency"
  }()

  private static let anglerContextPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "ANGLER_CONTEXT_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/angler-context"
  }()

  private static func logConfig() {
    AppLogging.log("AnglerAboutYou config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .trip)
    AppLogging.log("AnglerAboutYou config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .trip)
    AppLogging.log("AnglerAboutYou config — PROFICIENCY_URL: '\(proficiencyPath)'", level: .debug, category: .trip)
    AppLogging.log("AnglerAboutYou config — API_BASE_URL (raw): '\(rawBaseURLString)'", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou config — API_BASE_URL (normalized): '\(baseURLString)'", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou config — PROFICIENCY_URL: '\(proficiencyPath)'", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou config — ANGLER_CONTEXT_URL: '\(anglerContextPath)'", level: .debug, category: .angler)
  }

  private static func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    AppLogging.log("AnglerAboutYou makeURL start — base(raw): '\(rawBaseURLString)', base(normalized): '\(baseURLString)', path: '\(path)'", level: .debug, category: .angler)
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else {
      AppLogging.log("AnglerAboutYou invalid API_BASE_URL — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .debug, category: .trip)
      AppLogging.log("AnglerAboutYou makeURL invalid base — raw: '\(rawBaseURLString)', normalized: '\(baseURLString)'", level: .debug, category: .angler)
      throw NSError(domain: "AnglerAboutYou", code: -1000, userInfo: [
        NSLocalizedDescriptionKey: "Invalid API_BASE_URL (raw: '\(rawBaseURLString)', normalized: '\(baseURLString)')"
      ])
    }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    AppLogging.log("AnglerAboutYou makeURL components — scheme: \(scheme), host: \(host), port: \(String(describing: base.port)), basePath: '\(base.path)', normalizedBasePath: '\(normalizedBasePath)', normalizedPath: '\(normalizedPath)'", level: .debug, category: .angler)
    comps.path = normalizedBasePath + normalizedPath

    let existing = base.query != nil ? (URLComponents(string: base.absoluteString)?.queryItems ?? []) : []
    let merged = existing + queryItems
    comps.queryItems = merged.isEmpty ? nil : merged
    AppLogging.log({
      let qi = comps.queryItems?.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&") ?? "<none>"
      return "AnglerAboutYou makeURL composed — path: '\(comps.path)', query: \(qi)"
    }, level: .debug, category: .angler)

    guard let url = comps.url else {
      AppLogging.log("AnglerAboutYou makeURL failed to build URL for path: \(path)", level: .debug, category: .angler)
      throw NSError(domain: "AnglerAboutYou", code: -1001, userInfo: [
        NSLocalizedDescriptionKey: "Failed to build URL for path: \(path)"
      ])
    }
    AppLogging.log("AnglerAboutYou makeURL success — URL: \(url.absoluteString)", level: .debug, category: .angler)
    return url
  }

  static func proficiencyURL() throws -> URL {
    logConfig()
    let url = try makeURL(path: proficiencyPath)
    AppLogging.log("AnglerAboutYou proficiencyURL => \(url.absoluteString)", level: .debug, category: .angler)
    return url
  }
    static func anglerContextURL() throws -> URL {
        logConfig()
        return try makeURL(path: anglerContextPath)
      }
}

struct AnglerAboutYou: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared
  @State private var showUnsavedConfirm = false

  @State private var isSaving = false
  @State private var infoText: String?
  @State private var showSavedAlert = false
  @State private var isLoading = false
  @State private var errorText: String?

  // API-provided context (we'll use the first available context for display)
  @State private var context: AnglerContext?

  // Local cache key helper (uses IDs now)
  private func cacheKey(anglerId: String, species: String, tactic: String) -> String {
    "proficiency_\(anglerId)_\(species)_\(tactic)"
  }

  // Slider values 1..100 for each category
  @State private var learningStyleValue: Double = 50
  @State private var castingValue: Double = 50
  @State private var wadingValue: Double = 50
  @State private var hikingValue: Double = 50

  // Originals for dirty tracking
  @State private var originalLearningStyleValue: Double = 50
  @State private var originalCastingValue: Double = 50
  @State private var originalWadingValue: Double = 50
  @State private var originalHikingValue: Double = 50
  private var isDirty: Bool {
    abs(learningStyleValue - originalLearningStyleValue) > 0.0001 ||
    abs(castingValue - originalCastingValue) > 0.0001 ||
    abs(wadingValue - originalWadingValue) > 0.0001 ||
    abs(hikingValue - originalHikingValue) > 0.0001
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let err = errorText { Text(err).foregroundColor(.red).font(.footnote) }
          if let info = infoText { Text(info).foregroundColor(.gray).font(.footnote) }

          if isLoading {
            ProgressView().tint(.blue)
          } else if let ctx = context {
            Text("Instructions: Please answer a few quick questions to personalize your experience. Drag the slider toward the option that fits best. If you’re between two options, place it somewhere in the middle")
              .foregroundColor(.white)
              .font(.subheadline)

            // Learning Style
            CategoryCard(
              title: "Learning Style",
              contextText: ctx.learning_style_context,
              question: ctx.learning_style_question,
              low: ctx.learning_style_low,
              medium: ctx.learning_style_medium,
              high: ctx.learning_style_high,
              slider: Binding(get: { learningStyleValue }, set: { learningStyleValue = $0 })
            )

            // Casting
            CategoryCard(
              title: "Casting",
              contextText: ctx.casting_context,
              question: ctx.casting_question,
              low: ctx.casting_low,
              medium: ctx.casting_medium,
              high: ctx.casting_high,
              slider: Binding(get: { castingValue }, set: { castingValue = $0 })
            )

            // Wading
            CategoryCard(
              title: "Wading",
              contextText: ctx.wading_context ?? ctx.mobility_context,
              question: ctx.wading_question ?? ctx.mobility_question,
              low: ctx.wading_low ?? ctx.mobility_low,
              medium: ctx.wading_medium ?? ctx.mobility_medium,
              high: ctx.wading_high ?? ctx.mobility_high,
              slider: Binding(get: { wadingValue }, set: { wadingValue = $0 })
            )

            // Hiking
            CategoryCard(
              title: "Hiking",
              contextText: ctx.hiking_context ?? ctx.gear_context,
              question: ctx.hiking_question ?? ctx.gear_question,
              low: ctx.hiking_low ?? ctx.gear_low,
              medium: ctx.hiking_medium ?? ctx.gear_medium,
              high: ctx.hiking_high ?? ctx.gear_high,
              slider: Binding(get: { hikingValue }, set: { hikingValue = $0 })
            )
          } else {
            Text("No context available.")
              .foregroundColor(.gray)
          }

          Spacer(minLength: 12)
        }
        .padding(.horizontal)
        .padding(.top)
      }
    }
    .task { await loadContext() }
    .navigationTitle("Self-assessment")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: {
          if isDirty { showUnsavedConfirm = true } else { dismiss() }
        }) {
          Image(systemName: "chevron.left")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { Task {
          isSaving = true
          let ok = await saveAboutYou()
          isSaving = false
          if ok {
            originalLearningStyleValue = learningStyleValue
            originalCastingValue = castingValue
            originalWadingValue = wadingValue
            originalHikingValue = hikingValue
            dismiss()
          }
        } }) {
          HStack(spacing: 6) {
            if isSaving { ProgressView() }
            Text("Save")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background((isDirty && !isSaving && auth.currentAnglerNumber != nil) ? Color.blue : Color.gray)
              .clipShape(Capsule())
          }
        }
        .buttonStyle(.plain)
        .disabled(auth.currentAnglerNumber == nil || !isDirty || isSaving)
      }
    }
    .alert("Thank you", isPresented: $showSavedAlert) {
      Button("OK") { dismiss() }
        .tint(.blue)
    } message: {
      Text("You can update your profile at any time")
    }
    .confirmationDialog(
      "You have unsaved changes",
      isPresented: $showUnsavedConfirm,
      titleVisibility: .visible
    ) {
      Button("Save Changes") { Task { _ = await saveAboutYou(); dismiss() } }
      Button("Discard Changes", role: .destructive) { dismiss() }
      Button("Cancel", role: .cancel) {}
    }
    .preferredColorScheme(.dark)
  }

  private struct CategoryCard: View {
    let title: String
    let contextText: String?
    let question: String?
    let low: String?
    let medium: String?
    let high: String?
    @Binding var slider: Double // 1..100

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.headline.weight(.semibold))
          .foregroundColor(.blue)

        if let contextText, !contextText.isEmpty {
          Text(String(contextText.prefix(150)))
            .font(.subheadline)
            .foregroundColor(.white)
        }

        if let question, !question.isEmpty {
          Text(String(question.prefix(100)))
            .font(.subheadline)
            .italic()
            .foregroundColor(.white)
        }

        Slider(value: $slider, in: 1...100, step: 1)

        HStack(alignment: .top) {
          VStack(alignment: .leading) {
            Text(low.map { String($0.prefix(150)) } ?? "")
              .foregroundColor(.gray)
              .font(.footnote)
              .lineLimit(3)
              .multilineTextAlignment(.leading)
          }
          Spacer()
          VStack(alignment: .center) {
            Text(medium.map { String($0.prefix(150)) } ?? "")
              .foregroundColor(.gray)
              .font(.footnote)
              .lineLimit(3)
              .multilineTextAlignment(.center)
          }
          Spacer()
          VStack(alignment: .trailing) {
            Text(high.map { String($0.prefix(150)) } ?? "")
              .foregroundColor(.gray)
              .font(.footnote)
              .lineLimit(3)
              .multilineTextAlignment(.trailing)
          }
        }
      }
      .padding()
      .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
  }

  // Save results to server
  private func saveAboutYou() async -> Bool {
    guard let anglerId = auth.currentAnglerNumber, !anglerId.isEmpty else { return false }
    let tokenOpt = await auth.currentAccessToken()
    guard let token = tokenOpt, !token.isEmpty else { return false }

    AppLogging.log("AnglerAboutYou saveAboutYou — token present=\(!token.isEmpty), anglerId=\(anglerId)", level: .debug, category: .angler)

    let speciesId = context?.species?.id ?? ""
    let tacticId = context?.tactics?.id ?? ""
    let lodgeId = context?.lodges?.id ?? ""

    do {
      struct ProficiencyBody: Encodable {
        let angler_id: String
        let species_id: String
        let tactic_id: String
        let lodge_id: String
        let casting: Int
        let wading: Int
        let hiking: Int
        let learning_style: Int
      }

      let postURL = try AnglerAboutYouAPI.proficiencyURL()
      var postReq = URLRequest(url: postURL)
      postReq.httpMethod = "POST"
      postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
      postReq.setValue("application/json", forHTTPHeaderField: "Accept")
      postReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      postReq.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

      AppLogging.log("AnglerAboutYou POST — URL: \(postURL.absoluteString)", level: .debug, category: .angler)
      AppLogging.log("AnglerAboutYou POST — Method: \(postReq.httpMethod ?? "<nil>")", level: .debug, category: .angler)
      AppLogging.log("AnglerAboutYou POST — Headers: Authorization=Bearer <redacted>, apikey prefix=\(auth.publicAnonKey.prefix(8))…", level: .debug, category: .angler)

      let body = ProficiencyBody(
        angler_id: anglerId,
        species_id: speciesId,
        tactic_id: tacticId,
        lodge_id: lodgeId,
        casting: Int(castingValue.rounded()),
        wading: Int(wadingValue.rounded()),
        hiking: Int(hikingValue.rounded()),
        learning_style: Int(learningStyleValue.rounded())
      )
      postReq.httpBody = try JSONEncoder().encode(body)

      if let httpBody = postReq.httpBody,
         let obj = try? JSONSerialization.jsonObject(with: httpBody),
         let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
         let prettyStr = String(data: pretty, encoding: .utf8) {
        AppLogging.log("AnglerAboutYou POST — Body =>\n\(prettyStr)", level: .debug, category: .angler)
      }

      let (data, response) = try await URLSession.shared.data(for: postReq)

      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      AppLogging.log("AnglerAboutYou POST — Status: \(status)", level: .debug, category: .angler)
      if let obj = try? JSONSerialization.jsonObject(with: data),
         let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
         let prettyStr = String(data: pretty, encoding: .utf8) {
        AppLogging.log("AnglerAboutYou POST — Response JSON =>\n\(prettyStr)", level: .debug, category: .angler)
      } else if let raw = String(data: data, encoding: .utf8) {
        AppLogging.log("AnglerAboutYou POST — Response raw =>\n\(raw)", level: .debug, category: .angler)
      }

      guard (200..<300).contains(status) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        AppLogging.log("AnglerAboutYou save failed (\(status)) body: \(body)", level: .debug, category: .trip)
        if !body.isEmpty { errorText = "Save failed (\(status)): \(body)" } else { errorText = "Save failed (\(status))." }
        return false
      }

      // On success, sync originals
      originalLearningStyleValue = learningStyleValue
      originalCastingValue = castingValue
      originalWadingValue = wadingValue
      originalHikingValue = hikingValue

      // Cache locally
      if let anglerId = auth.currentAnglerNumber {
        let key = cacheKey(anglerId: anglerId, species: speciesId, tactic: tacticId)
        let dict: [String: Int] = [
          "learning_style": Int(learningStyleValue.rounded()),
          "casting": Int(castingValue.rounded()),
          "wading": Int(wadingValue.rounded()),
          "hiking": Int(hikingValue.rounded())
        ]
        UserDefaults.standard.set(dict, forKey: key)
      }

      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }

  private func loadContext() async {
    isLoading = true
    errorText = nil
    defer { isLoading = false }

    let tokenOpt = await auth.currentAccessToken()
    guard let token = tokenOpt, !token.isEmpty else { errorText = "You are not signed in."; return }

    AppLogging.log("AnglerAboutYou loadContext — token present=\(!token.isEmpty)", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou loadContext — anglerContextURL=\(String(describing: AppEnvironment.shared.anglerContextURL))", level: .debug, category: .angler)

      let url: URL
      do {
        url = try AnglerAboutYouAPI.anglerContextURL()
      } catch {
        errorText = error.localizedDescription
        return
      }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    AppLogging.log("AnglerAboutYou Context GET — URL: \(url.absoluteString)", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou Context GET — Method: \(req.httpMethod ?? "<nil>")", level: .debug, category: .angler)
    AppLogging.log("AnglerAboutYou Context GET — Headers: Authorization=Bearer <redacted>, apikey prefix=\(auth.publicAnonKey.prefix(8))…", level: .debug, category: .angler)

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      AppLogging.log("AnglerAboutYou Context GET — Status: \(code)", level: .debug, category: .angler)
      if let obj = try? JSONSerialization.jsonObject(with: data),
         let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
         let prettyStr = String(data: pretty, encoding: .utf8) {
        AppLogging.log("AnglerAboutYou Context GET — Response JSON =>\n\(prettyStr)", level: .debug, category: .angler)
      } else if let raw = String(data: data, encoding: .utf8) {
        AppLogging.log("AnglerAboutYou Context GET — Response raw =>\n\(raw)", level: .debug, category: .angler)
      }
      guard (200..<300).contains(code) else { errorText = "Load failed (\(code))."; return }
      let decoded = try JSONDecoder().decode(AnglerContextResponse.self, from: data)
      context = decoded.contexts.first

      let speciesId = context?.species?.id ?? ""
      let tacticId = context?.tactics?.id ?? ""

      // First try server GET
      do {
        let profURL = try AnglerAboutYouAPI.proficiencyURL()
        var pReq = URLRequest(url: profURL)
        pReq.httpMethod = "GET"
        pReq.setValue("application/json", forHTTPHeaderField: "Accept")
        pReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        pReq.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

        AppLogging.log("AnglerAboutYou Proficiency GET — URL: \(profURL.absoluteString)", level: .debug, category: .angler)
        AppLogging.log("AnglerAboutYou Proficiency GET — Method: \(pReq.httpMethod ?? "<nil>")", level: .debug, category: .angler)
        AppLogging.log("AnglerAboutYou Proficiency GET — Headers: Authorization=Bearer <redacted>, apikey prefix=\(auth.publicAnonKey.prefix(8))…", level: .debug, category: .angler)

        let (pData, pResp) = try await URLSession.shared.data(for: pReq)
        let pCode = (pResp as? HTTPURLResponse)?.statusCode ?? -1
        AppLogging.log("AnglerAboutYou Proficiency GET — Status: \(pCode)", level: .debug, category: .angler)
        if let obj = try? JSONSerialization.jsonObject(with: pData),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: pretty, encoding: .utf8) {
          AppLogging.log("AnglerAboutYou Proficiency GET — Response JSON =>\n\(prettyStr)", level: .debug, category: .angler)
        } else if let raw = String(data: pData, encoding: .utf8) {
          AppLogging.log("AnglerAboutYou Proficiency GET — Response raw =>\n\(raw)", level: .debug, category: .angler)
        }

        if (200..<300).contains(pCode) {
          struct ProficiencyResponse: Decodable { let proficiencies: [Proficiency] }
          struct Proficiency: Decodable {
            let species_id: String
            let tactic_id: String
            let lodge_id: String?
            let casting: Int?
            let wading: Int?
            let hiking: Int?
            let learning_style: Int?
          }

          let profDecoded = try JSONDecoder().decode(ProficiencyResponse.self, from: pData)

          let lodgeId = context?.lodges?.id
          let exact = profDecoded.proficiencies.first { p in
            let lodgeOk = (lodgeId == nil) || (p.lodge_id == lodgeId)
            return p.species_id == speciesId && p.tactic_id == tacticId && lodgeOk
          }
          let speciesTactic = profDecoded.proficiencies.first { p in p.species_id == speciesId && p.tactic_id == tacticId }
          let speciesOnly = profDecoded.proficiencies.first { p in p.species_id == speciesId }
          let match = exact ?? speciesTactic ?? speciesOnly ?? profDecoded.proficiencies.first

          if let m = match {
            learningStyleValue = Double(m.learning_style ?? 50)
            castingValue = Double(m.casting ?? 50)
            wadingValue = Double(m.wading ?? 50)
            hikingValue = Double(m.hiking ?? 50)
            originalLearningStyleValue = learningStyleValue
            originalCastingValue = castingValue
            originalWadingValue = wadingValue
            originalHikingValue = hikingValue
          } else {
            // No server record; try local cache
            if let anglerId = auth.currentAnglerNumber {
              let key = cacheKey(anglerId: anglerId, species: speciesId, tactic: tacticId)
              if let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] {
                learningStyleValue = Double(dict["learning_style"] ?? 50)
                castingValue = Double(dict["casting"] ?? 50)
                wadingValue = Double(dict["wading"] ?? 50)
                hikingValue = Double(dict["hiking"] ?? 50)
              } else {
                learningStyleValue = 50
                castingValue = 50
                wadingValue = 50
                hikingValue = 50
              }
              originalLearningStyleValue = learningStyleValue
              originalCastingValue = castingValue
              originalWadingValue = wadingValue
              originalHikingValue = hikingValue
            }
          }
        } else {
          // Server GET failed; use local cache if available
          let key = auth.currentAnglerNumber.map { cacheKey(anglerId: $0, species: speciesId, tactic: tacticId) }
          if let key, let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] {
            learningStyleValue = Double(dict["learning_style"] ?? 50)
            castingValue = Double(dict["casting"] ?? 50)
            wadingValue = Double(dict["wading"] ?? 50)
            hikingValue = Double(dict["hiking"] ?? 50)
          } else {
            learningStyleValue = 50
            castingValue = 50
            wadingValue = 50
            hikingValue = 50
          }
          originalLearningStyleValue = learningStyleValue
          originalCastingValue = castingValue
          originalWadingValue = wadingValue
          originalHikingValue = hikingValue
        }
      } catch {
        // Network or decode error; fall back to local cache or defaults
        let key = auth.currentAnglerNumber.map { cacheKey(anglerId: $0, species: speciesId, tactic: tacticId) }
        if let key, let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] {
          learningStyleValue = Double(dict["learning_style"] ?? 50)
          castingValue = Double(dict["casting"] ?? 50)
          wadingValue = Double(dict["wading"] ?? 50)
          hikingValue = Double(dict["hiking"] ?? 50)
        } else {
          learningStyleValue = 50
          castingValue = 50
          wadingValue = 50
          hikingValue = 50
        }
        originalLearningStyleValue = learningStyleValue
        originalCastingValue = castingValue
        originalWadingValue = wadingValue
        originalHikingValue = hikingValue
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
}

#Preview {
  AnglerAboutYou()
}
