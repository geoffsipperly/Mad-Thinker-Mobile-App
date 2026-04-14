// AnglerOnboardingWizard.swift
// SkeenaSystem
//
// Full-screen step-by-step onboarding wizard for anglers joining
// Lodge, MultiLodge, or FlyShop communities. Walks through profile,
// preferences, proficiencies, and gear setup.
//
// Triggered once per community via UserDefaults key
// "anglerOnboarded_\(communityId)". Skippable at any point.

import SwiftUI
import Foundation

// MARK: - Wizard

struct AnglerOnboardingWizard: View {
  let communityId: String
  let onComplete: () -> Void

  @StateObject private var auth = AuthService.shared
  @ObservedObject private var communityService = CommunityService.shared

  @State private var currentStep = 0
  @State private var showSkipConfirm = false

  private let totalSteps = 5  // welcome, profile, preferences, proficiencies, gear

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        // Top bar: close button + progress
        HStack {
          Button(action: { showSkipConfirm = true }) {
            Image(systemName: "xmark")
              .font(.title3.weight(.semibold))
              .foregroundColor(.white.opacity(0.7))
          }
          Spacer()
          Text("Step \(min(currentStep + 1, totalSteps)) of \(totalSteps)")
            .font(.caption.weight(.medium))
            .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)

        // Progress bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.white.opacity(0.12))
              .frame(height: 4)
            Capsule()
              .fill(Color.blue)
              .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
              .animation(.easeInOut(duration: 0.3), value: currentStep)
          }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

        // Step content
        Group {
          switch currentStep {
          case 0: WelcomeStep(communityConfig: communityService.activeCommunityConfig)
          case 1: ProfileStep(auth: auth)
          case 2: PreferencesStep(communityId: communityId, auth: auth)
          case 3: ProficienciesStep(communityId: communityId, auth: auth)
          case 4: GearStep(communityId: communityId, auth: auth)
          default: EmptyView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Bottom navigation buttons
        HStack(spacing: 12) {
          if currentStep > 0 {
            Button(action: { withAnimation { currentStep -= 1 } }) {
              Text("Back")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }

          if currentStep > 0 {
            Button(action: { advanceOrFinish() }) {
              Text("Skip")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }

          Button(action: {
            if currentStep == 0 {
              advanceOrFinish()
            } else {
              // Post a save notification for the current step, then advance
              NotificationCenter.default.post(name: .onboardingStepSave, object: nil)
              // Delay advance slightly so the step can save
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                advanceOrFinish()
              }
            }
          }) {
            Text(currentStep == totalSteps - 1 ? "Done" : (currentStep == 0 ? "Get Started" : "Save & Next"))
              .font(.subheadline.weight(.semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(Color.blue)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
      }
    }
    .preferredColorScheme(.dark)
    .confirmationDialog(
      "Skip setup?",
      isPresented: $showSkipConfirm,
      titleVisibility: .visible
    ) {
      Button("Skip Setup", role: .destructive) { onComplete() }
      Button("Continue Setup", role: .cancel) {}
    } message: {
      Text("You can always update your profile, preferences, and gear from the menu later.")
    }
  }

  private func advanceOrFinish() {
    if currentStep < totalSteps - 1 {
      withAnimation { currentStep += 1 }
    } else {
      onComplete()
    }
  }
}

// MARK: - Save notification

extension Notification.Name {
  static let onboardingStepSave = Notification.Name("onboardingStepSave")
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
  let communityConfig: CommunityConfig

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer(minLength: 24)

        CommunityLogoView(config: communityConfig, size: 120)

        if let name = communityConfig.displayName, !name.isEmpty {
          Text("Welcome to \(name)")
            .font(.title2.weight(.bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
        } else {
          Text("Welcome")
            .font(.title2.weight(.bold))
            .foregroundColor(.white)
        }

        Text("Let's get you set up so your guide can personalize your experience.")
          .font(.body)
          .foregroundColor(.gray)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)

        VStack(alignment: .leading, spacing: 16) {
          setupRow(icon: "person.fill", title: "Your Profile", desc: "Name and contact details")
          setupRow(icon: "slider.horizontal.3", title: "Preferences", desc: "Dietary needs, accessibility, and more")
          setupRow(icon: "chart.bar.fill", title: "Experience Level", desc: "Help us match you with the right activities")
          setupRow(icon: "backpack.fill", title: "Gear Checklist", desc: "Know what to pack before you arrive")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)

        Spacer(minLength: 24)
      }
    }
  }

  private func setupRow(icon: String, title: String, desc: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.blue)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.white)
        Text(desc)
          .font(.caption)
          .foregroundColor(.gray)
      }
      Spacer()
    }
  }
}

// MARK: - Step 1: Profile

private struct ProfileStep: View {
  @ObservedObject var auth: AuthService

  @State private var profile = MyProfile()
  @State private var dobDate = Date()
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var isSaving = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Your Profile")
          .font(.title3.weight(.bold))
          .foregroundColor(.white)
        Text("Confirm your details so your guide knows who you are.")
          .font(.subheadline)
          .foregroundColor(.gray)

        if let err = errorText {
          Text(err).foregroundColor(.red).font(.footnote)
        }

        if isLoading {
          ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 32)
        } else {
          profileCard(label: "First Name", value: Binding(
            get: { profile.firstName ?? "" },
            set: { profile.firstName = $0 }
          ))
          profileCard(label: "Last Name", value: Binding(
            get: { profile.lastName ?? "" },
            set: { profile.lastName = $0 }
          ))

          VStack(alignment: .leading, spacing: 8) {
            Text("Date of Birth").foregroundColor(.blue).font(.callout.weight(.medium))
            DatePicker("", selection: $dobDate, displayedComponents: .date)
              .labelsHidden()
              .foregroundColor(.white)
          }
          .padding()
          .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

          profileCard(label: "Phone Number", value: Binding(
            get: { profile.phoneNumber ?? "" },
            set: { profile.phoneNumber = $0 }
          ))
        }

        Spacer(minLength: 16)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
    }
    .task { await loadProfile() }
    .onReceive(NotificationCenter.default.publisher(for: .onboardingStepSave)) { _ in
      Task { await saveProfile() }
    }
  }

  private func profileCard(label: String, value: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).foregroundColor(.blue).font(.callout.weight(.medium))
      TextField(label, text: value)
        .foregroundColor(.white)
        .font(.callout)
    }
    .padding()
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  private func loadProfile() async {
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? ManageProfileAPI.url() else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? -1) else { return }
      struct Resp: Decodable { let profile: MyProfile }
      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      profile = decoded.profile
      if let dob = profile.dateOfBirth, !dob.isEmpty {
        if let d = DateFormatting.ymd.date(from: dob) { dobDate = d }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveProfile() async {
    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? ManageProfileAPI.url() else { return }

    profile.dateOfBirth = DateFormatting.ymd.string(from: dobDate)

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

    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: req)
  }
}

// MARK: - Step 2: Preferences

private struct PreferencesStep: View {
  let communityId: String
  @ObservedObject var auth: AuthService

  @State private var fields: [PreferenceField] = []
  @State private var values: [String: Bool] = [:]
  @State private var textValues: [String: String] = [:]
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Preferences")
          .font(.title3.weight(.bold))
          .foregroundColor(.white)
        Text("Let us know about any dietary needs, accessibility requirements, or other preferences.")
          .font(.subheadline)
          .foregroundColor(.gray)

        if let err = errorText {
          Text(err).foregroundColor(.red).font(.footnote)
        }

        if isLoading {
          ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if fields.isEmpty {
          Text("No preferences configured for this community.")
            .foregroundColor(.gray).font(.body)
        } else {
          ForEach(fields) { field in
            preferenceCard(field)
          }
        }

        Spacer(minLength: 16)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
    }
    .task { await loadPreferences() }
    .onReceive(NotificationCenter.default.publisher(for: .onboardingStepSave)) { _ in
      Task { await savePreferences() }
    }
  }

  @ViewBuilder
  private func preferenceCard(_ field: PreferenceField) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        Text(field.question_text ?? field.field_label)
          .foregroundColor(.white)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 0) {
          checkButton(isOn: values[field.id] == false, label: "No") {
            values[field.id] = false
            textValues[field.id] = ""
          }
          .frame(width: 56, alignment: .center)

          checkButton(isOn: values[field.id] == true, label: "Yes") {
            values[field.id] = true
          }
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

  private func checkButton(isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: isOn ? "checkmark.square" : "square")
          .foregroundColor(.white).font(.subheadline)
        Text(label).foregroundColor(.white).font(.footnote)
      }
    }
    .buttonStyle(.plain)
  }

  private func loadPreferences() async {
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.url(communityId: communityId, category: "preference") else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? -1) else { return }
      struct Resp: Decodable { let preferences: [PreferenceField] }
      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.preferences.sorted { $0.sort_order < $1.sort_order }

      for field in fields {
        let rawValue = field.value ?? "false"
        let boolPart = rawValue.split(separator: "|", maxSplits: 1).first.map(String.init) ?? rawValue
        values[field.id] = boolPart == "true"
        if let tv = field.text_value, !tv.isEmpty {
          textValues[field.id] = tv
        } else if rawValue.contains("|") {
          textValues[field.id] = rawValue.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        } else {
          textValues[field.id] = ""
        }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func savePreferences() async {
    guard !fields.isEmpty else { return }
    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.postURL() else { return }

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

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: req)
  }
}

// MARK: - Step 3: Proficiencies

private struct ProficienciesStep: View {
  let communityId: String
  @ObservedObject var auth: AuthService

  @State private var fields: [ProficiencyField] = []
  @State private var values: [String: Double] = [:]
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("About You")
          .font(.title3.weight(.bold))
          .foregroundColor(.white)
        Text("Drag the slider toward the option that fits best. If you're between two options, place it somewhere in the middle.")
          .font(.subheadline)
          .foregroundColor(.gray)

        if let err = errorText {
          Text(err).foregroundColor(.red).font(.footnote)
        }

        if isLoading {
          ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if fields.isEmpty {
          Text("No proficiency fields configured for this community.")
            .foregroundColor(.gray).font(.body)
        } else {
          ForEach(fields) { field in
            proficiencyCard(field)
          }
        }

        Spacer(minLength: 16)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
    }
    .task { await loadProficiencies() }
    .onReceive(NotificationCenter.default.publisher(for: .onboardingStepSave)) { _ in
      Task { await saveProficiencies() }
    }
  }

  @ViewBuilder
  private func proficiencyCard(_ field: ProficiencyField) -> some View {
    let minVal = Double(field.options?.min ?? 1)
    let maxVal = Double(field.options?.max ?? 100)

    VStack(alignment: .leading, spacing: 12) {
      Text(field.field_label)
        .font(.headline.weight(.semibold))
        .foregroundColor(.blue)

      if let ctx = field.context_text, !ctx.isEmpty {
        Text(String(ctx.prefix(150)))
          .font(.subheadline)
          .foregroundColor(.white)
      }

      if let q = field.question_text, !q.isEmpty {
        Text(String(q.prefix(100)))
          .font(.subheadline).italic()
          .foregroundColor(.white)
      }

      Slider(
        value: Binding(
          get: { values[field.id] ?? ((minVal + maxVal) / 2) },
          set: { values[field.id] = $0 }
        ),
        in: minVal...maxVal,
        step: 1
      )
      .gesture(DragGesture(minimumDistance: 0))

      HStack(alignment: .top) {
        Text(field.options?.lowText.map { String($0.prefix(150)) } ?? "")
          .foregroundColor(.gray).font(.footnote)
          .lineLimit(3).multilineTextAlignment(.leading)
        Spacer()
        Text(field.options?.midText.map { String($0.prefix(150)) } ?? "")
          .foregroundColor(.gray).font(.footnote)
          .lineLimit(3).multilineTextAlignment(.center)
        Spacer()
        Text(field.options?.highText.map { String($0.prefix(150)) } ?? "")
          .foregroundColor(.gray).font(.footnote)
          .lineLimit(3).multilineTextAlignment(.trailing)
      }
    }
    .padding()
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  private func loadProficiencies() async {
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.url(communityId: communityId, category: "proficiency") else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? -1) else { return }
      struct Resp: Decodable { let proficiencies: [ProficiencyField] }
      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.proficiencies.sorted { $0.sort_order < $1.sort_order }

      for field in fields {
        let defaultVal = Double((field.options?.min ?? 1) + (field.options?.max ?? 100)) / 2.0
        if let valStr = field.value, let val = Double(valStr) {
          values[field.id] = val
        } else {
          values[field.id] = defaultVal
        }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveProficiencies() async {
    guard !fields.isEmpty else { return }
    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.postURL() else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": "\(Int(val.rounded()))"]
    }

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: req)
  }
}

// MARK: - Step 4: Gear

private struct GearStep: View {
  let communityId: String
  @ObservedObject var auth: AuthService

  @State private var fields: [GearField] = []
  @State private var values: [String: String] = [:]
  @State private var isLoading = false
  @State private var errorText: String?

  private var mandatoryFields: [GearField] {
    fields.filter { ($0.options?.priority ?? "") == "mandatory" }.sorted { $0.sort_order < $1.sort_order }
  }
  private var recommendedFields: [GearField] {
    fields.filter { ($0.options?.priority ?? "") == "recommended" }.sorted { $0.sort_order < $1.sort_order }
  }
  private var otherFields: [GearField] {
    fields.filter { let p = $0.options?.priority ?? ""; return p != "mandatory" && p != "recommended" }
      .sorted { $0.sort_order < $1.sort_order }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Gear Checklist")
          .font(.title3.weight(.bold))
          .foregroundColor(.white)
        Text("Check off the gear you already have. This helps your guide know what you might need.")
          .font(.subheadline)
          .foregroundColor(.gray)

        if let err = errorText {
          Text(err).foregroundColor(.red).font(.footnote)
        }

        if isLoading {
          ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if fields.isEmpty {
          Text("No gear items configured for this community.")
            .foregroundColor(.gray).font(.body)
        } else {
          if !mandatoryFields.isEmpty {
            Text("Mandatory gear")
              .font(.headline.weight(.semibold)).foregroundColor(.blue)
            Text("These items are essential for a safe and comfortable trip")
              .foregroundColor(.white).font(.subheadline)
            gearSection(mandatoryFields)
          }
          if !recommendedFields.isEmpty {
            Text("Recommended gear")
              .font(.headline.weight(.semibold)).foregroundColor(.blue)
            gearSection(recommendedFields)
          }
          if !otherFields.isEmpty {
            Text("Additional gear")
              .font(.headline.weight(.semibold)).foregroundColor(.blue)
            gearSection(otherFields)
          }
        }

        Spacer(minLength: 16)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
    }
    .task { await loadGear() }
    .onReceive(NotificationCenter.default.publisher(for: .onboardingStepSave)) { _ in
      Task { await saveGear() }
    }
  }

  private func gearSection(_ items: [GearField]) -> some View {
    VStack(spacing: 12) {
      ForEach(items) { field in
        HStack(alignment: .top, spacing: 12) {
          Button(action: {
            values[field.id] = values[field.id] == "true" ? "false" : "true"
          }) {
            ZStack {
              RoundedRectangle(cornerRadius: 2)
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 16, height: 16)
              if values[field.id] == "true" {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
                  .font(.system(size: 10, weight: .bold))
              }
            }
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(field.field_label)
              .foregroundColor(.white).font(.body)
            if let ctx = field.context_text, !ctx.isEmpty {
              Text(ctx).foregroundColor(.gray).font(.subheadline)
            }
          }
          Spacer()
        }
      }
    }
  }

  private func loadGear() async {
    isLoading = true
    defer { isLoading = false }

    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.url(communityId: communityId, category: "gear") else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? -1) else { return }
      struct Resp: Decodable { let gear: [GearField] }
      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      fields = decoded.gear.sorted { $0.sort_order < $1.sort_order }
      for field in fields {
        values[field.id] = field.value ?? "false"
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveGear() async {
    guard !fields.isEmpty else { return }
    guard let token = await auth.currentAccessToken(), !token.isEmpty else { return }
    guard let url = try? MemberProfileFieldsAPI.postURL() else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.publicAnonKey, forHTTPHeaderField: "apikey")

    let valuesArray = values.map { (fieldId, val) -> [String: String] in
      ["field_definition_id": fieldId, "value": val]
    }

    let body: [String: Any] = ["community_id": communityId, "values": valuesArray]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: req)
  }
}
