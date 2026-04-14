// Bend Fly Shop
// AnglerAboutYou.swift
//
// Self-assessment view driven by the member-profile-fields API (category=proficiency).
// Field definitions (label, question, slider labels) come from the server.
// Uses shared MemberProfileFieldsAPI for URL composition.

import SwiftUI
import Foundation

// MARK: - Models

struct ProficiencyField: Decodable, Identifiable {
  let id: String
  let field_name: String
  let field_label: String
  let field_type: String
  let question_text: String?
  let context_text: String?
  let options: ProficiencyOptions?
  let is_required: Bool
  let sort_order: Int
  let value: String?
}

struct ProficiencyOptions: Decodable {
  let min: Int?
  let max: Int?
  // Server may use either naming convention
  let low: String?
  let medium: String?
  let high: String?
  let low_label: String?
  let mid_label: String?
  let high_label: String?

  var lowText: String? { low_label ?? low }
  var midText: String? { mid_label ?? medium }
  var highText: String? { high_label ?? high }
}

// MARK: - View

struct AnglerAboutYou: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @State private var fields: [ProficiencyField] = []
  @State private var values: [String: Double] = [:]          // field_id -> slider value
  @State private var originalValues: [String: Double] = [:]

  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var infoText: String?
  @State private var showUnsavedConfirm = false
  @State private var showSavedAlert = false

  private var communityId: String? { communityService.activeCommunityId }

  private var hasUnsavedChanges: Bool {
    for (key, val) in values {
      if abs(val - (originalValues[key] ?? 50)) > 0.0001 { return true }
    }
    return false
  }

  private var cacheKey: String {
    let cid = communityId ?? "unknown"
    let mid = auth.currentMemberId ?? "unknown"
    return "proficiency_fields_\(mid)_\(cid)"
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let err = errorText { Text(err).foregroundColor(.red).font(.footnote) }
          if let info = infoText { Text(info).foregroundColor(.gray).font(.footnote) }

          if isLoading && fields.isEmpty {
            ProgressView().tint(.blue)
          } else if fields.isEmpty {
            Text("No proficiency fields configured for this community.")
              .foregroundColor(.gray)
          } else {
            Text("Instructions: Please answer a few quick questions to personalize your experience. Drag the slider toward the option that fits best. If you're between two options, place it somewhere in the middle")
              .foregroundColor(.white)
              .font(.subheadline)

            ForEach(fields) { field in
              CategoryCard(
                title: field.field_label,
                contextText: field.context_text,
                question: field.question_text,
                low: field.options?.lowText,
                medium: field.options?.midText,
                high: field.options?.highText,
                minVal: Double(field.options?.min ?? 1),
                maxVal: Double(field.options?.max ?? 100),
                slider: Binding(
                  get: { values[field.id] ?? 50 },
                  set: { values[field.id] = $0 }
                )
              )
            }
          }

          Spacer(minLength: 12)
        }
        .padding(.horizontal)
        .padding(.top)
      }
    }
    .task { await loadProficiency() }
    .navigationTitle("Self-assessment")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: {
          if hasUnsavedChanges { showUnsavedConfirm = true } else { dismiss() }
        }) {
          Image(systemName: "chevron.left")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { Task {
          isSaving = true
          let ok = await saveProficiency()
          isSaving = false
          if ok {
            originalValues = values
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
              .background((hasUnsavedChanges && !isSaving) ? Color.blue : Color.gray)
              .clipShape(Capsule())
          }
        }
        .buttonStyle(.plain)
        .disabled(!hasUnsavedChanges || isSaving)
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
      Button("Save Changes") { Task { _ = await saveProficiency(); dismiss() } }
      Button("Discard Changes", role: .destructive) { dismiss() }
      Button("Cancel", role: .cancel) {}
    }
    .preferredColorScheme(.dark)
  }

  // MARK: - CategoryCard (slider UI)

  private struct CategoryCard: View {
    let title: String
    let contextText: String?
    let question: String?
    let low: String?
    let medium: String?
    let high: String?
    var minVal: Double = 1
    var maxVal: Double = 100
    @Binding var slider: Double

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

        Slider(value: $slider, in: minVal...maxVal, step: 1)
          .gesture(DragGesture(minimumDistance: 0))  // Prioritize slider over ScrollView

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

  // MARK: - Networking

  private func loadProficiency() async {
    errorText = nil
    infoText = nil
    isLoading = true
    defer { isLoading = false }

    guard let cid = communityId, !cid.isEmpty else {
      loadFromCache()
      return
    }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      loadFromCache()
      return
    }

    let url: URL
    do {
      url = try MemberProfileFieldsAPI.url(communityId: cid, category: "proficiency")
    } catch {
      errorText = "Unsupported URL (check API_BASE_URL / MEMBER_PROFILE_FIELDS_URL)."
      loadFromCache()
      return
    }

    AppLogging.log("[SelfAssessment] loadProficiency URL: \(url.absoluteString)", level: .debug, category: .network)

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      AppLogging.log("[SelfAssessment] loadProficiency status: \(code)", level: .debug, category: .network)

      guard (200..<300).contains(code) else {
        errorText = "Load failed (\(code))."
        loadFromCache()
        return
      }

      struct Resp: Decodable {
        let proficiencies: [ProficiencyField]
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.proficiencies.sorted { $0.sort_order < $1.sort_order }

      var loaded: [String: Double] = [:]
      for field in fields {
        let defaultVal = Double((field.options?.min ?? 1) + (field.options?.max ?? 100)) / 2.0
        if let valStr = field.value, let val = Double(valStr) {
          loaded[field.id] = val
        } else {
          loaded[field.id] = defaultVal
        }
      }
      values = loaded
      originalValues = loaded

      saveToCache()
    } catch {
      errorText = error.localizedDescription
      loadFromCache()
    }
  }

  private func saveProficiency() async -> Bool {
    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      errorText = "You are not signed in."
      return false
    }

    guard let cid = communityId, !cid.isEmpty else {
      errorText = "No community selected."
      return false
    }

    let url: URL
    do {
      url = try MemberProfileFieldsAPI.postURL()
    } catch {
      errorText = "Unsupported URL."
      return false
    }

    AppLogging.log("[SelfAssessment] saveProficiency URL: \(url.absoluteString)", level: .debug, category: .network)

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": "\(Int(val.rounded()))"]
    }

    let body: [String: Any] = [
      "community_id": cid,
      "values": valuesArray
    ]

    do {
      req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      AppLogging.log("[SelfAssessment] saveProficiency status: \(code)", level: .debug, category: .network)

      guard (200..<300).contains(code) else {
        let msg = String(data: data, encoding: .utf8) ?? "Save failed."
        errorText = "Save failed (\(code)): \(msg)"
        return false
      }

      originalValues = values
      saveToCache()
      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }

  // MARK: - Cache

  private func saveToCache() {
    guard !fields.isEmpty else { return }
    let cached: [[String: Any]] = fields.map { field -> [String: Any] in
      var dict: [String: Any] = [:]
      dict["id"] = field.id
      dict["field_name"] = field.field_name
      dict["field_label"] = field.field_label
      dict["field_type"] = field.field_type
      dict["question_text"] = field.question_text ?? ""
      dict["context_text"] = field.context_text ?? ""
      dict["min"] = field.options?.min ?? 1
      dict["max"] = field.options?.max ?? 100
      dict["low_label"] = field.options?.lowText ?? ""
      dict["mid_label"] = field.options?.midText ?? ""
      dict["high_label"] = field.options?.highText ?? ""
      dict["is_required"] = field.is_required
      dict["sort_order"] = field.sort_order
      dict["value"] = values[field.id].map { String(Int($0.rounded())) } ?? ""
      return dict
    }
    UserDefaults.standard.set(cached, forKey: cacheKey)
  }

  private func loadFromCache() {
    guard let cached = UserDefaults.standard.array(forKey: cacheKey) as? [[String: Any]] else { return }

    var cachedFields: [ProficiencyField] = []
    var cachedValues: [String: Double] = [:]

    for dict in cached {
      guard let id = dict["id"] as? String,
            let fieldName = dict["field_name"] as? String,
            let fieldLabel = dict["field_label"] as? String,
            let fieldType = dict["field_type"] as? String
      else { continue }

      let minVal = dict["min"] as? Int ?? 1
      let maxVal = dict["max"] as? Int ?? 100
      let options = ProficiencyOptions(
        min: minVal,
        max: maxVal,
        low: nil,
        medium: nil,
        high: nil,
        low_label: dict["low_label"] as? String,
        mid_label: dict["mid_label"] as? String,
        high_label: dict["high_label"] as? String
      )

      let valStr = dict["value"] as? String ?? ""
      let val = Double(valStr) ?? Double(minVal + maxVal) / 2.0

      let field = ProficiencyField(
        id: id,
        field_name: fieldName,
        field_label: fieldLabel,
        field_type: fieldType,
        question_text: dict["question_text"] as? String,
        context_text: dict["context_text"] as? String,
        options: options,
        is_required: dict["is_required"] as? Bool ?? false,
        sort_order: dict["sort_order"] as? Int ?? 0,
        value: valStr.isEmpty ? nil : valStr
      )
      cachedFields.append(field)
      cachedValues[id] = val
    }

    fields = cachedFields.sorted { $0.sort_order < $1.sort_order }
    values = cachedValues
    originalValues = cachedValues
  }
}

#Preview {
  AnglerAboutYou()
}
