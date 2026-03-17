// Bend Fly Shop
// ManageProfileView.swift
//
// Drop-in refactor:
// - loadProfile() and saveProfile() now compose URL using:
//     API_BASE_URL + MY_PROFILE_URL
//   (both read from Info.plist, with safe normalization)

import SwiftUI
import Foundation

// MARK: - Models

struct MyProfile: Codable, Equatable {
  var firstName: String?
  var lastName: String?
  var anglerNumber: String?
  var dateOfBirth: String?
  var phoneNumber: String?
}

struct Preferences: Codable, Equatable {
  var drinks: Bool?
  var drinksText: String?
  var food: Bool?
  var foodText: String?
  var health: Bool?
  var healthText: String?
  var occasion: Bool?
  var occasionText: String?
  var allergies: Bool?
  var allergiesText: String?
  var cpap: Bool?
  var cpapText: String?
}

// MARK: - UI Helpers

struct Checkbox: View {
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

// MARK: - API Helper (URL composition convention)

enum ManageProfileAPI {
  // Change this if your endpoint expects POST/PATCH instead of PUT
  static let saveMethod = "PUT" // "PATCH" or "POST" if needed

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

    // Allow API_BASE_URL to include an optional base path
    let basePath = base.path
    let normalizedBasePath =
      basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)

    let normalizedPath = profilePath.hasPrefix("/") ? profilePath : "/" + profilePath
    comps.path = normalizedBasePath + normalizedPath

    // Preserve any query items already present in API_BASE_URL (rare, but safe)
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
  @State private var preferences = Preferences()
  @State private var originalPreferences = Preferences()

  private var hasUnsavedChanges: Bool { (originalProfile != profile) || (originalPreferences != preferences) }

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
            Section {
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
                  Text("Please enter a valid phone number (10–15 digits, digits only or formatted).")
                    .font(.caption)
                    .foregroundColor(.red)
                }
              }
            }

            Section(header: Text("Set preferences").foregroundColor(.blue)) { EmptyView() }

            preferenceYesNoSection(
              title: "While on the river do you have any beverage requests beyond water and coffee?",
              value: Binding(get: { preferences.drinks }, set: { preferences.drinks = $0 }),
              text: Binding(get: { preferences.drinksText ?? "" }, set: { preferences.drinksText = $0 }),
              placeholder: "Tell us what you’d like (e.g., Coke, Coke Zero, sparkling water, sports drinks, beer)"
            )

            preferenceYesNoSection(
              title: "Are there any foods you prefer not to be served at the lodge?",
              value: Binding(get: { preferences.food }, set: { preferences.food = $0 }),
              text: Binding(get: { preferences.foodText ?? "" }, set: { preferences.foodText = $0 }),
              placeholder: "Tell us what to avoid (e.g., seafood, mushrooms, spicy foods, cilantro)."
            )

            preferenceYesNoSection(
              title: "Do you have any health conditions we should know about?",
              value: Binding(get: { preferences.health }, set: { preferences.health = $0 }),
              text: Binding(get: { preferences.healthText ?? "" }, set: { preferences.healthText = $0 }),
              placeholder: "Please describe (e.g., asthma, diabetes, heart condition, recent injury, mobility limits)."
            )

            preferenceYesNoSection(
              title: "Are you celebrating a special occasion on this trip?",
              value: Binding(get: { preferences.occasion }, set: { preferences.occasion = $0 }),
              text: Binding(get: { preferences.occasionText ?? "" }, set: { preferences.occasionText = $0 }),
              placeholder: "What are you celebrating? (e.g., birthday, anniversary, honeymoon, graduation)"
            )

            preferenceYesNoSection(
              title: "Do you have any food or medication allergies?",
              value: Binding(get: { preferences.allergies }, set: { preferences.allergies = $0 }),
              text: Binding(get: { preferences.allergiesText ?? "" }, set: { preferences.allergiesText = $0 }),
              placeholder: "List the allergy and severity (e.g., peanuts—anaphylaxis; penicillin—rash)."
            )

            preferenceYesNoSection(
              title: "Will you bring a CPAP or other medical device that needs power?",
              value: Binding(get: { preferences.cpap }, set: { preferences.cpap = $0 }),
              text: Binding(get: { preferences.cpapText ?? "" }, set: { preferences.cpapText = $0 }),
              placeholder: "What device is it, and when do you need power? (e.g., overnight CPAP, charger, nebulizer)."
            )
          }
          .scrollContentBackground(.hidden)
          .background(Color.black)
        } else {
          // iOS 15 fallback (keeps your layout behavior)
          Form {
            Section {
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
                  Text("Please enter a valid phone number (10–15 digits, digits only or formatted).")
                    .font(.caption)
                    .foregroundColor(.red)
                }
              }
            }

            Section(header: Text("Preferences").foregroundColor(.blue)) { EmptyView() }

            // Keep your existing iOS 15 preference UI behavior
            preferenceYesNoSection_iOS15(
              title: "Do you have any beverage requests beyond water and coffee?",
              value: Binding(get: { preferences.drinks }, set: { preferences.drinks = $0 }),
              text: Binding(get: { preferences.drinksText ?? "" }, set: { preferences.drinksText = $0 }),
              placeholder: "Tell us what you’d like (e.g., Coke, Coke Zero, sparkling water, sports drinks, beer)"
            )

            preferenceYesNoSection_iOS15(
              title: "Are there any foods you prefer not to be served at the lodge?",
              value: Binding(get: { preferences.food }, set: { preferences.food = $0 }),
              text: Binding(get: { preferences.foodText ?? "" }, set: { preferences.foodText = $0 }),
              placeholder: "Tell us what to avoid (e.g., seafood, mushrooms, spicy foods, cilantro)."
            )

            preferenceYesNoSection_iOS15(
              title: "Do you have any health conditions we should know about?",
              value: Binding(get: { preferences.health }, set: { preferences.health = $0 }),
              text: Binding(get: { preferences.healthText ?? "" }, set: { preferences.healthText = $0 }),
              placeholder: "Please describe (e.g., asthma, diabetes, heart condition, recent injury, mobility limits)."
            )

            preferenceYesNoSection_iOS15(
              title: "Are you celebrating a special occasion on this trip?",
              value: Binding(get: { preferences.occasion }, set: { preferences.occasion = $0 }),
              text: Binding(get: { preferences.occasionText ?? "" }, set: { preferences.occasionText = $0 }),
              placeholder: "What are you celebrating? (e.g., birthday, anniversary, honeymoon, graduation)"
            )

            preferenceYesNoSection_iOS15(
              title: "Do you have any food or medication allergies?",
              value: Binding(get: { preferences.allergies }, set: { preferences.allergies = $0 }),
              text: Binding(get: { preferences.allergiesText ?? "" }, set: { preferences.allergiesText = $0 }),
              placeholder: "List the allergy and severity (e.g., peanuts—anaphylaxis; penicillin—rash)."
            )

            preferenceYesNoSection_iOS15(
              title: "Will you bring a CPAP or other medical device that needs power?",
              value: Binding(get: { preferences.cpap }, set: { preferences.cpap = $0 }),
              text: Binding(get: { preferences.cpapText ?? "" }, set: { preferences.cpapText = $0 }),
              placeholder: "What device is it, and when do you need power? (e.g., overnight CPAP, charger, nebulizer)."
            )
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

  // MARK: - Preference UI helpers (shared)

  @ViewBuilder
  @available(iOS 16.0, *)
  private func preferenceYesNoSection(
    title: String,
    value: Binding<Bool?>,
    text: Binding<String>,
    placeholder: String
  ) -> some View {
    Section {
      HStack(alignment: .center) {
        Text(title)
          .foregroundColor(.white)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 0) {
          Checkbox(isOn: !(value.wrappedValue ?? false), label: "No", action: { value.wrappedValue = false })
            .frame(width: 56, alignment: .center)
          Checkbox(isOn: (value.wrappedValue ?? false), label: "Yes", action: { value.wrappedValue = true })
            .frame(width: 56, alignment: .center)
        }
      }

      if value.wrappedValue == true {
        TextField(placeholder, text: text, axis: .vertical)
          .lineLimit(3, reservesSpace: true)
          .foregroundColor(.white)
      }
    }
  }

  @ViewBuilder
  private func preferenceYesNoSection_iOS15(
    title: String,
    value: Binding<Bool?>,
    text: Binding<String>,
    placeholder: String
  ) -> some View {
    Section {
      HStack(alignment: .center) {
        Text(title)
          .foregroundColor(.white)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 0) {
          Checkbox(isOn: !(value.wrappedValue ?? false), label: "No", action: { value.wrappedValue = false })
            .frame(width: 56, alignment: .center)
          Checkbox(isOn: (value.wrappedValue ?? false), label: "Yes", action: { value.wrappedValue = true })
            .frame(width: 56, alignment: .center)
        }
      }

      if (text.wrappedValue).isEmpty {
        Text(placeholder).foregroundColor(.gray).font(.caption)
      }

      if value.wrappedValue == true {
        TextEditor(text: text)
          .foregroundColor(.white)
          .frame(minHeight: 72)
      }
    }
  }

  // MARK: - Validation

  private func isValidPhone(_ s: String) -> Bool {
    let digits = s.filter { $0.isNumber }
    return digits.count >= 10 && digits.count <= 15
  }

  // MARK: - Networking (refactored to composed URL)

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
        let preferences: Preferences?
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)

      profile = decoded.profile
      preferences = decoded.preferences ?? Preferences()

      // Parse DOB into DatePicker state
      if let dob = profile.dateOfBirth, !dob.isEmpty {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: dob) { dobDate = d }
      }

      originalProfile = profile
      originalPreferences = preferences
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

    // Sync dobDate back to yyyy-MM-dd
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

    // Body (keep your “only send meaningful fields” behavior, but include booleans when set)
    var body: [String: Any] = [:]
    if let v = profile.firstName, !v.isEmpty { body["firstName"] = v }
    if let v = profile.lastName, !v.isEmpty { body["lastName"] = v }
    if let v = profile.phoneNumber, !v.isEmpty { body["phoneNumber"] = v }
    if let v = profile.dateOfBirth, !v.isEmpty { body["dateOfBirth"] = v }

    if let v = preferences.drinks { body["drinks"] = v }
    if let v = preferences.drinksText, !v.isEmpty { body["drinksText"] = v }
    if let v = preferences.food { body["food"] = v }
    if let v = preferences.foodText, !v.isEmpty { body["foodText"] = v }
    if let v = preferences.health { body["health"] = v }
    if let v = preferences.healthText, !v.isEmpty { body["healthText"] = v }
    if let v = preferences.occasion { body["occasion"] = v }
    if let v = preferences.occasionText, !v.isEmpty { body["occasionText"] = v }
    if let v = preferences.allergies { body["allergies"] = v }
    if let v = preferences.allergiesText, !v.isEmpty { body["allergiesText"] = v }
    if let v = preferences.cpap { body["cpap"] = v }
    if let v = preferences.cpapText, !v.isEmpty { body["cpapText"] = v }

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

      // If server echoes back updated profile/preferences, you can decode it here.
      // We keep your original behavior: accept success and dismiss.
      infoText = "Saved."
      originalProfile = profile
      originalPreferences = preferences
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
