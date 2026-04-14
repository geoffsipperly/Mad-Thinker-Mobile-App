// Bend Fly Shop
// ManagePreferencesView.swift
//
// Preferences view driven by the member-profile-fields API (category=preference).
// Each field renders as a yes/no question with optional detail text.
// Uses shared MemberProfileFieldsAPI for URL composition.

import SwiftUI
import Foundation

// MARK: - Models

struct PreferenceField: Decodable, Identifiable {
  let id: String
  let field_name: String
  let field_label: String
  let field_type: String
  let question_text: String?
  let context_text: String?
  let options: PreferenceOptions?
  let is_required: Bool
  let sort_order: Int
  let value: String?       // "true" or "false"
  let text_value: String?  // detail text
}

struct PreferenceOptions: Decodable {
  let has_details: Bool?
  let details_prompt: String?
}

// MARK: - Checkbox (yes/no toggle)

private struct PreferenceCheckbox: View {
  var isOn: Bool
  var label: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: isOn ? "checkmark.square" : "square")
          .foregroundColor(.white)
          .font(.subheadline)
        if !label.isEmpty {
          Text(label)
            .foregroundColor(.white)
            .font(.footnote)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - View

struct ManagePreferencesView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @State private var fields: [PreferenceField] = []
  @State private var values: [String: Bool] = [:]          // field_id -> true/false
  @State private var textValues: [String: String] = [:]    // field_id -> detail text
  @State private var originalValues: [String: Bool] = [:]
  @State private var originalTextValues: [String: String] = [:]

  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var infoText: String?
  @State private var showUnsavedConfirm = false

  private var communityId: String? { communityService.activeCommunityId }

  private var hasUnsavedChanges: Bool {
    values != originalValues || textValues != originalTextValues
  }

  private var cacheKey: String {
    let cid = communityId ?? "unknown"
    let mid = auth.currentMemberId ?? "unknown"
    return "preference_fields_\(mid)_\(cid)"
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if isLoading && fields.isEmpty {
        ProgressView().tint(.white)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let err = errorText {
              Text(err).foregroundColor(.red).font(.footnote)
            }
            if let info = infoText {
              Text(info).foregroundColor(.gray).font(.footnote)
            }

            if fields.isEmpty && !isLoading {
              Text("No preferences configured for this community.")
                .foregroundColor(.gray)
                .font(.body)
            } else {
              Text("Set preferences")
                .font(.headline.weight(.semibold))
                .foregroundColor(.blue)

              ForEach(fields) { field in
                preferenceSection(field)
              }
            }

            Spacer(minLength: 32)
          }
          .padding(.horizontal)
          .padding(.top)
        }
      }
    }
    .navigationTitle("Preferences")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .preferredColorScheme(.dark)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: {
          if hasUnsavedChanges { showUnsavedConfirm = true } else { dismiss() }
        }) {
          Image(systemName: "chevron.left")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { Task { await save() } }) {
          HStack(spacing: 6) {
            if isSaving { ProgressView().tint(.white) }
            Text("Save")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(hasUnsavedChanges && !isSaving ? Color.blue : Color.gray)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!hasUnsavedChanges || isSaving)
      }
    }
    .confirmationDialog(
      "You have unsaved changes",
      isPresented: $showUnsavedConfirm,
      titleVisibility: .visible
    ) {
      Button("Save Changes") { Task { await save() } }
      Button("Discard Changes", role: .destructive) { dismiss() }
      Button("Cancel", role: .cancel) {}
    }
    .task { await loadPreferences() }
  }

  // MARK: - Preference Section

  @ViewBuilder
  private func preferenceSection(_ field: PreferenceField) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        Text(field.question_text ?? field.field_label)
          .foregroundColor(.white)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 0) {
          PreferenceCheckbox(
            isOn: values[field.id] == false,
            label: "No",
            action: {
              values[field.id] = false
              textValues[field.id] = ""
            }
          )
          .frame(width: 56, alignment: .center)

          PreferenceCheckbox(
            isOn: values[field.id] == true,
            label: "Yes",
            action: { values[field.id] = true }
          )
          .frame(width: 56, alignment: .center)
        }
      }

      if values[field.id] == true, field.options?.has_details == true {
        if #available(iOS 16.0, *) {
          TextField(
            field.options?.details_prompt ?? "Please provide details",
            text: Binding(
              get: { textValues[field.id] ?? "" },
              set: { textValues[field.id] = $0 }
            ),
            axis: .vertical
          )
          .lineLimit(3, reservesSpace: true)
          .foregroundColor(.white)
          .font(.callout)
          .padding(8)
          .background(Color.white.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          TextEditor(text: Binding(
            get: { textValues[field.id] ?? "" },
            set: { textValues[field.id] = $0 }
          ))
          .foregroundColor(.white)
          .frame(minHeight: 72)
          .padding(4)
          .background(Color.white.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
    }
    .padding()
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  // MARK: - Networking

  private func loadPreferences() async {
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
      url = try MemberProfileFieldsAPI.url(communityId: cid, category: "preference")
    } catch {
      errorText = "Unsupported URL (check API_BASE_URL / MEMBER_PROFILE_FIELDS_URL)."
      loadFromCache()
      return
    }

    #if DEBUG
    print("[Preferences] loadPreferences URL: \(url.absoluteString)")
    #endif

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      #if DEBUG
      print("[Preferences] loadPreferences status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[Preferences] loadPreferences body preview:\n\(preview)")
      #endif

      guard (200..<300).contains(code) else {
        errorText = "Load failed (\(code))."
        loadFromCache()
        return
      }

      struct Resp: Decodable {
        let preferences: [PreferenceField]
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.preferences.sorted { $0.sort_order < $1.sort_order }

      var loadedVals: [String: Bool] = [:]
      var loadedText: [String: String] = [:]
      for field in fields {
        // value may be "true", "false", or "true|detail text"
        let rawValue = field.value ?? "false"
        let boolPart = rawValue.split(separator: "|", maxSplits: 1).first.map(String.init) ?? rawValue
        loadedVals[field.id] = boolPart == "true"
        // text_value comes as a separate field, but also parse from pipe format as fallback
        if let tv = field.text_value, !tv.isEmpty {
          loadedText[field.id] = tv
        } else if rawValue.contains("|") {
          let textPart = rawValue.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
          loadedText[field.id] = textPart
        } else {
          loadedText[field.id] = ""
        }
      }
      values = loadedVals
      textValues = loadedText
      originalValues = loadedVals
      originalTextValues = loadedText

      saveToCache()
    } catch {
      errorText = error.localizedDescription
      loadFromCache()
    }
  }

  private func save() async {
    errorText = nil
    infoText = nil
    isSaving = true
    defer { isSaving = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      errorText = "You are not signed in."
      return
    }

    guard let cid = communityId, !cid.isEmpty else {
      errorText = "No community selected."
      return
    }

    let url: URL
    do {
      url = try MemberProfileFieldsAPI.postURL()
    } catch {
      errorText = "Unsupported URL."
      return
    }

    #if DEBUG
    print("[Preferences] save URL: \(url.absoluteString)")
    #endif

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    let valuesArray: [[String: String]] = fields.map { field in
      let boolVal = values[field.id] == true
      let text = textValues[field.id] ?? ""
      let valueStr: String

      if boolVal && field.options?.has_details == true && !text.isEmpty {
        valueStr = "true|\(text)"
      } else {
        valueStr = boolVal ? "true" : "false"
      }

      return ["field_definition_id": field.id, "value": valueStr]
    }

    let body: [String: Any] = [
      "community_id": cid,
      "values": valuesArray
    ]

    do {
      req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      #if DEBUG
      print("[Preferences] save status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[Preferences] save body preview:\n\(preview)")
      #endif

      guard (200..<300).contains(code) else {
        let msg = String(data: data, encoding: .utf8) ?? "Save failed."
        errorText = "Save failed (\(code)): \(msg)"
        return
      }

      infoText = "Saved."
      originalValues = values
      originalTextValues = textValues
      saveToCache()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }

  // MARK: - Cache

  private func saveToCache() {
    guard !fields.isEmpty else { return }
    let cached: [[String: Any]] = fields.map { field in
      [
        "id": field.id,
        "field_name": field.field_name,
        "field_label": field.field_label,
        "field_type": field.field_type,
        "question_text": field.question_text ?? "",
        "context_text": field.context_text ?? "",
        "has_details": field.options?.has_details ?? false,
        "details_prompt": field.options?.details_prompt ?? "",
        "is_required": field.is_required,
        "sort_order": field.sort_order,
        "value": values[field.id] == true ? "true" : "false",
        "text_value": textValues[field.id] ?? ""
      ]
    }
    UserDefaults.standard.set(cached, forKey: cacheKey)
  }

  private func loadFromCache() {
    guard let cached = UserDefaults.standard.array(forKey: cacheKey) as? [[String: Any]] else { return }

    var cachedFields: [PreferenceField] = []
    var cachedValues: [String: Bool] = [:]
    var cachedText: [String: String] = [:]

    for dict in cached {
      guard let id = dict["id"] as? String,
            let fieldName = dict["field_name"] as? String,
            let fieldLabel = dict["field_label"] as? String,
            let fieldType = dict["field_type"] as? String
      else { continue }

      let hasDetails = dict["has_details"] as? Bool ?? false
      let detailsPrompt = dict["details_prompt"] as? String
      let options = PreferenceOptions(
        has_details: hasDetails,
        details_prompt: detailsPrompt
      )

      let valStr = dict["value"] as? String ?? "false"
      let textVal = dict["text_value"] as? String ?? ""

      let field = PreferenceField(
        id: id,
        field_name: fieldName,
        field_label: fieldLabel,
        field_type: fieldType,
        question_text: dict["question_text"] as? String,
        context_text: dict["context_text"] as? String,
        options: options,
        is_required: dict["is_required"] as? Bool ?? false,
        sort_order: dict["sort_order"] as? Int ?? 0,
        value: valStr,
        text_value: textVal.isEmpty ? nil : textVal
      )
      cachedFields.append(field)
      cachedValues[id] = valStr == "true"
      cachedText[id] = textVal
    }

    fields = cachedFields.sorted { $0.sort_order < $1.sort_order }
    values = cachedValues
    textValues = cachedText
    originalValues = cachedValues
    originalTextValues = cachedText
  }
}

#Preview {
  NavigationView {
    ManagePreferencesView()
  }
}
