// Bend Fly Shop
// ManageProfileView.swift
//
// Profile-only view (name, phone, DOB).
// Preferences are managed separately via the member-profile-fields API.
//
// URL composition:
//   API_BASE_URL + MY_PROFILE_URL (both from Info.plist)

import SwiftUI
import Foundation

// MARK: - Models

struct MyProfile: Codable, Equatable {
  var firstName: String?
  var lastName: String?
  var memberId: String?
  var dateOfBirth: String?
  var phoneNumber: String?
}

// MARK: - API Helper (URL composition convention)

enum ManageProfileAPI {
  static let saveMethod = "PUT"

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

  private static let profilePath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "MY_PROFILE_URL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    ?? "/functions/v1/my-profile"
  }()

  static func url() throws -> URL {
    guard let base = URL(string: baseURLString),
          let scheme = base.scheme,
          let host = base.host
    else { throw URLError(.badURL) }

    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)

    let normalizedPath = profilePath.hasPrefix("/") ? profilePath : "/" + profilePath
    comps.path = normalizedBasePath + normalizedPath

    let existing = base.query != nil
      ? (URLComponents(string: base.absoluteString)?.queryItems ?? [])
      : []
    comps.queryItems = existing.isEmpty ? nil : existing

    guard let url = comps.url else { throw URLError(.badURL) }
    return url
  }
}

// MARK: - View

struct ManageProfileView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var auth: AuthService

  @State private var profile = MyProfile()
  @State private var originalProfile = MyProfile()
  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var infoText: String?
  @State private var showUnsavedConfirm = false

  @State private var dobDate: Date = Date()
  @State private var originalDobDate: Date = Date()

  private var hasUnsavedChanges: Bool { originalProfile != profile || dobDate != originalDobDate }

  var body: some View {
    DarkPageTemplate {
      VStack(alignment: .leading, spacing: 16) {
        if let err = errorText {
          Text(err).foregroundColor(.red).font(.footnote)
        }
        if let info = infoText {
          Text(info).foregroundColor(.gray).font(.footnote)
        }

        if #available(iOS 16.0, *) {
          Form {
            profileFields
          }
          .scrollContentBackground(.hidden)
          .background(Color.black)
        } else {
          Form {
            profileFields
          }
          .background(Color.black)
        }

        Spacer()
      }
      .padding(.top, 8)
    }
    .navigationTitle("Manage Profile")
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: {
          if hasUnsavedChanges { showUnsavedConfirm = true } else { dismiss() }
        }) { Image(systemName: "chevron.left")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { Task { await saveProfile() } }) {
          HStack(spacing: 6) {
            if isSaving { ProgressView() }
            Text("Save")
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background((hasUnsavedChanges && !isSaving && !isLoading) ? Color.blue : Color.gray)
              .clipShape(Capsule())
          }
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isLoading)
      }
    }
    .confirmationDialog(
      "You have unsaved changes",
      isPresented: $showUnsavedConfirm,
      titleVisibility: .visible
    ) {
      Button("Save Changes") { Task { await saveProfile() } }
      Button("Discard Changes", role: .destructive) { dismiss() }
      Button("Cancel", role: .cancel) {}
    }
    .task { await loadProfile() }
  }

  // MARK: - Profile Fields

  @ViewBuilder
  private var profileFields: some View {
    Section {
      if let memberId = profile.memberId, !memberId.isEmpty {
        HStack {
          Text("Member #").foregroundColor(.blue).font(.callout)
          Spacer()
          Text(memberId)
            .foregroundColor(.gray)
            .font(.callout)
        }
      }
      HStack {
        Text("First Name").foregroundColor(.blue).font(.callout)
        Spacer()
        TextField("First name", text: Binding(get: { profile.firstName ?? "" }, set: { profile.firstName = $0 }))
          .multilineTextAlignment(.trailing)
          .foregroundColor(.white)
          .font(.callout)
      }
      HStack {
        Text("Last Name").foregroundColor(.blue).font(.callout)
        Spacer()
        TextField("Last name", text: Binding(get: { profile.lastName ?? "" }, set: { profile.lastName = $0 }))
          .multilineTextAlignment(.trailing)
          .foregroundColor(.white)
          .font(.callout)
      }
      HStack {
        Text("Date of Birth").foregroundColor(.blue).font(.callout)
        Spacer()
        DatePicker("Date of Birth", selection: $dobDate, displayedComponents: .date)
          .labelsHidden()
          .foregroundColor(.white)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Phone Number").foregroundColor(.blue).font(.callout)
          Spacer()
          TextField("Phone number", text: Binding(get: { profile.phoneNumber ?? "" }, set: { profile.phoneNumber = $0 }))
            .multilineTextAlignment(.trailing)
            .foregroundColor(.white)
            .font(.callout)
        }
        if let phone = profile.phoneNumber, !phone.isEmpty, !isValidPhone(phone) {
          Text("Please enter a valid phone number (10\u{2013}15 digits, digits only or formatted).")
            .font(.caption)
            .foregroundColor(.red)
        }
      }
    }
  }

  // MARK: - Validation

  private func isValidPhone(_ s: String) -> Bool {
    let digits = s.filter { $0.isNumber }
    return digits.count >= 10 && digits.count <= 15
  }

  // MARK: - Networking

  private func loadProfile() async {
    errorText = nil
    infoText = nil
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      errorText = "You are not signed in."
      return
    }

    let url: URL
    do {
      url = try ManageProfileAPI.url()
    } catch {
      errorText = "Unsupported URL (check API_BASE_URL / MY_PROFILE_URL)."
      #if DEBUG
      print("[ManageProfile] URL compose error: \(error)")
      #endif
      return
    }

    #if DEBUG
    print("[ManageProfile] loadProfile URL: \(url.absoluteString)")
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
      print("[ManageProfile] loadProfile status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[ManageProfile] loadProfile body preview:\n\(preview)")
      #endif

      guard (200..<300).contains(code) else {
        errorText = "Load failed (\(code))."
        return
      }

      struct Resp: Decodable {
        let profile: MyProfile
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)

      profile = decoded.profile

      if let dob = profile.dateOfBirth, !dob.isEmpty {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: dob) { dobDate = d }
      }

      originalProfile = profile
      originalDobDate = dobDate
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveProfile() async {
    errorText = nil
    infoText = nil
    isSaving = true
    defer { isSaving = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else {
      errorText = "You are not signed in."
      return
    }

    if let phone = profile.phoneNumber, !phone.isEmpty, !isValidPhone(phone) {
      errorText = "Invalid phone number. Please correct it before saving."
      return
    }

    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd"
    profile.dateOfBirth = df.string(from: dobDate)

    let url: URL
    do {
      url = try ManageProfileAPI.url()
    } catch {
      errorText = "Unsupported URL (check API_BASE_URL / MY_PROFILE_URL)."
      #if DEBUG
      print("[ManageProfile] URL compose error: \(error)")
      #endif
      return
    }

    #if DEBUG
    print("[ManageProfile] saveProfile URL: \(url.absoluteString)")
    #endif

    var req = URLRequest(url: url)
    req.httpMethod = ManageProfileAPI.saveMethod
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    var body: [String: Any] = [:]
    if let v = profile.firstName, !v.isEmpty { body["firstName"] = v }
    if let v = profile.lastName, !v.isEmpty { body["lastName"] = v }
    if let v = profile.phoneNumber, !v.isEmpty { body["phoneNumber"] = v }
    if let v = profile.dateOfBirth, !v.isEmpty { body["dateOfBirth"] = v }

    do {
      req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      #if DEBUG
      print("[ManageProfile] saveProfile status: \(code)")
      let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-UTF8>"
      print("[ManageProfile] saveProfile body preview:\n\(preview)")
      #endif

      guard (200..<300).contains(code) else {
        let msg = String(data: data, encoding: .utf8) ?? ""
        errorText = "Save failed (\(code)). \(msg)"
        return
      }

      infoText = "Saved."
      originalProfile = profile
      originalDobDate = dobDate
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

#Preview {
  NavigationView {
    ManageProfileView()
      .environmentObject(AuthService.shared)
  }
}
