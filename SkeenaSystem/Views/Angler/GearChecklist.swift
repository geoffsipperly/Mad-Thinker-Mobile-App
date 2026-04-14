// Bend Fly Shop
// GearChecklist.swift
//
// Dynamic gear checklist driven by the member-profile-fields API.
// Field definitions (name, label, priority) come from the server,
// grouped by options.priority ("mandatory" / "recommended").
//
// URL composition:
//   API_BASE_URL + MEMBER_PROFILE_FIELDS_URL (both from Info.plist)

import SwiftUI
import Foundation

// MARK: - Models

struct GearField: Decodable, Identifiable {
  let id: String
  let field_name: String
  let field_label: String
  let field_type: String
  let question_text: String?
  let context_text: String?
  let options: GearFieldOptions?
  let is_required: Bool
  let sort_order: Int
  let value: String?
}

struct GearFieldOptions: Decodable {
  let priority: String?   // "mandatory" / "recommended"
}

// Uses shared MemberProfileFieldsAPI from Managers/MemberProfileFieldsAPI.swift

// MARK: - View

struct GearChecklist: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @State private var fields: [GearField] = []
  @State private var values: [String: String] = [:]       // field_id → "true"/"false"
  @State private var originalValues: [String: String] = [:]

  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var infoText: String?
  @State private var showSaveAlert = false
  @State private var saveSucceeded = false

  private var hasUnsavedChanges: Bool { values != originalValues }

  private var communityId: String? { communityService.activeCommunityId }

  private var cacheKey: String {
    let cid = communityId ?? "unknown"
    let mid = auth.currentMemberId ?? "unknown"
    return "gear_fields_\(mid)_\(cid)"
  }

  private var mandatoryFields: [GearField] {
    fields
      .filter { ($0.options?.priority ?? "") == "mandatory" }
      .sorted { $0.sort_order < $1.sort_order }
  }

  private var recommendedFields: [GearField] {
    fields
      .filter { ($0.options?.priority ?? "") == "recommended" }
      .sorted { $0.sort_order < $1.sort_order }
  }

  private var otherFields: [GearField] {
    fields
      .filter {
        let p = $0.options?.priority ?? ""
        return p != "mandatory" && p != "recommended"
      }
      .sorted { $0.sort_order < $1.sort_order }
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if isLoading && fields.isEmpty {
        ProgressView()
          .tint(.white)
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
              Text("No gear items configured for this community.")
                .foregroundColor(.gray)
                .font(.body)
            } else {
              if !mandatoryFields.isEmpty {
                Text("Mandatory gear")
                  .font(.headline.weight(.semibold))
                  .foregroundColor(.blue)

                Text("These items are essential for a safe and comfortable trip")
                  .foregroundColor(.white)
                  .font(.subheadline)

                fieldSection(mandatoryFields)
              }

              if !recommendedFields.isEmpty {
                Text("Recommended gear")
                  .font(.headline.weight(.semibold))
                  .foregroundColor(.blue)

                fieldSection(recommendedFields)
              }

              if !otherFields.isEmpty {
                Text("Additional gear")
                  .font(.headline.weight(.semibold))
                  .foregroundColor(.blue)

                fieldSection(otherFields)
              }
            }

            Spacer(minLength: 32)
          }
          .padding(.horizontal)
          .padding(.top)
        }
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
              infoText = "Saved"
            }
            saveSucceeded = ok
            showSaveAlert = true
          }
        } label: {
          HStack(spacing: 4) {
            if isSaving {
              ProgressView().tint(.white)
            }
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
    .alert(saveSucceeded ? "Saved" : "Save failed", isPresented: $showSaveAlert) {
      Button(action: { if saveSucceeded { dismiss() } }) {
        Text("OK").foregroundColor(.white)
      }
    } message: {
      if saveSucceeded {
        Text("Your gear checklist has been saved.")
      } else {
        Text(errorText ?? "We couldn't save your gear checklist. Please try again.")
      }
    }
    .tint(.blue)
    .task { await loadGear() }
  }

  // MARK: - Field Rendering

  private func fieldSection(_ items: [GearField]) -> some View {
    VStack(spacing: 12) {
      ForEach(items) { field in
        HStack(alignment: .top, spacing: 12) {
          Button(action: { toggleField(field) }) {
            let isOn = values[field.id] == "true"
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
          }

          VStack(alignment: .leading, spacing: 4) {
            Text(field.field_label)
              .foregroundColor(.white)
              .font(.body)
            if let context = field.context_text, !context.isEmpty {
              Text(context)
                .foregroundColor(.gray)
                .font(.subheadline)
            }
          }
          Spacer()
        }
      }
    }
  }

  private func toggleField(_ field: GearField) {
    let current = values[field.id] == "true"
    values[field.id] = current ? "false" : "true"
  }

  // MARK: - Networking

  private func loadGear() async {
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
      url = try MemberProfileFieldsAPI.url(communityId: cid, category: "gear")
    } catch {
      errorText = "Unsupported URL (check API_BASE_URL / MEMBER_PROFILE_FIELDS_URL)."
      #if DEBUG
      print("[GearChecklist] URL compose error: \(error)")
      #endif
      loadFromCache()
      return
    }

    #if DEBUG
    print("[GearChecklist] loadGear URL: \(url.absoluteString)")
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
      print("[GearChecklist] loadGear status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[GearChecklist] loadGear body preview:\n\(preview)")
      #endif

      guard (200..<300).contains(code) else {
        errorText = "Load failed (\(code))."
        loadFromCache()
        return
      }

      struct Resp: Decodable {
        let gear: [GearField]
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.gear.sorted { $0.sort_order < $1.sort_order }

      // Populate values from server response
      var loaded: [String: String] = [:]
      for field in fields {
        loaded[field.id] = field.value ?? "false"
      }
      values = loaded
      originalValues = loaded

      // Cache for offline
      saveToCache()
    } catch {
      errorText = error.localizedDescription
      loadFromCache()
    }
  }

  private func saveGear() async -> Bool {
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
      errorText = "Unsupported URL (check API_BASE_URL / MEMBER_PROFILE_FIELDS_URL)."
      return false
    }

    #if DEBUG
    print("[GearChecklist] saveGear URL: \(url.absoluteString)")
    #endif

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": val]
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
      print("[GearChecklist] saveGear status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[GearChecklist] saveGear body preview:\n\(preview)")
      #endif

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
    let cached: [[String: Any]] = fields.map { field in
      [
        "id": field.id,
        "field_name": field.field_name,
        "field_label": field.field_label,
        "field_type": field.field_type,
        "question_text": field.question_text ?? "",
        "context_text": field.context_text ?? "",
        "priority": field.options?.priority ?? "",
        "is_required": field.is_required,
        "sort_order": field.sort_order,
        "value": values[field.id] ?? "false"
      ]
    }
    UserDefaults.standard.set(cached, forKey: cacheKey)
  }

  private func loadFromCache() {
    guard let cached = UserDefaults.standard.array(forKey: cacheKey) as? [[String: Any]] else { return }

    var cachedFields: [GearField] = []
    var cachedValues: [String: String] = [:]

    for dict in cached {
      guard let id = dict["id"] as? String,
            let fieldName = dict["field_name"] as? String,
            let fieldLabel = dict["field_label"] as? String,
            let fieldType = dict["field_type"] as? String
      else { continue }

      let val = dict["value"] as? String ?? "false"
      let priority = dict["priority"] as? String
      let options = priority.flatMap { p in p.isEmpty ? nil : GearFieldOptions(priority: p) }

      let field = GearField(
        id: id,
        field_name: fieldName,
        field_label: fieldLabel,
        field_type: fieldType,
        question_text: dict["question_text"] as? String,
        context_text: dict["context_text"] as? String,
        options: options,
        is_required: dict["is_required"] as? Bool ?? false,
        sort_order: dict["sort_order"] as? Int ?? 0,
        value: val
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
  NavigationView {
    GearChecklist()
  }
}
