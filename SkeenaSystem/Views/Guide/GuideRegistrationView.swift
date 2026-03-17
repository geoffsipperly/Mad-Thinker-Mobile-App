// Bend Fly Shop

import SwiftUI
import UIKit

struct GuideRegistrationView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared

  // MARK: - Community

  enum Community: String, CaseIterable, Identifiable {
    case bendFlyShop = "Bend Fly Shop"

    var id: String { rawValue }
  }

  // MARK: - Constants

  private let supabaseSignupURL = AppEnvironment.shared.projectURL.appendingPathComponent("/auth/v1/signup")
  private let supabaseAnonKey = AppEnvironment.shared.anonKey

  // MARK: - Form fields

  @State private var userType: AuthService.UserType = .guide
  @State private var selectedCommunity: Community = .bendFlyShop

  @State private var firstName: String = ""
  @State private var lastName: String = ""
  @State private var anglerNumber: String = ""

  @State private var email: String = ""
  @State private var password: String = ""
  @State private var confirm: String = ""

  // MARK: - Hidden fields populated by scan (sent to API if available)

  enum Sex: String, CaseIterable, Identifiable { case male, female, other; var id: String { rawValue } }
  enum Residency: String, CaseIterable, Identifiable { case US, CA, other; var id: String { rawValue } }

  @State private var scannedDOB: Date?
  @State private var scannedSex: Sex?
  @State private var scannedMailingAddress: String?
  @State private var scannedTelephone: String?
  @State private var scannedResidency: Residency?

  // MARK: - UI state

  @State private var isBusy = false
  @State private var errorText: String?
  @State private var showAnglerLanding = false

  // OCR / Scan state
  @State private var showScanChoice = false
  @State private var showScanCamera = false
  @State private var showScanLibrary = false

  // Terms & Conditions
  @State private var hasAgreedToTerms = false
  @State private var showTermsSheet = false

  // MARK: - Password requirements

  private var hasMinLength: Bool { password.count >= 8 }
  private var hasUppercase: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
  private var hasLowercase: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
  private var hasNumber: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
  private var passwordMeetsRequirements: Bool { hasMinLength && hasUppercase && hasLowercase && hasNumber }
  private var passwordsMatch: Bool { !confirm.isEmpty && password == confirm }

  // MARK: - Derived state

  private var isPasswordValid: Bool {
    passwordMeetsRequirements && passwordsMatch
  }

  private var isEmailValid: Bool {
    let pattern = #"^\S+@\S+\.\S+$"#
    return email.range(of: pattern, options: .regularExpression) != nil
  }

  private var allFieldsFilled: Bool {
    let base = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && isEmailValid
    if userType == .angler {
      return base && !anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return base
  }

  private var canRegister: Bool {
    !isBusy && hasAgreedToTerms && isPasswordValid && allFieldsFilled
  }

    private var termsRole: TermsRole {
      userType == .guide ? .guide : .angler
    }

    private var termsTitle: String {
      TermsStore.title(for: termsRole)
    }

    private var termsBodyText: String {
      TermsStore.bodyText(for: termsRole)
    }

  // Shared style for compact fields
  private func fieldBackground<Content: View>(_ content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .frame(height: 40) // compact height
      .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      .foregroundColor(.white)
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      mainContent
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: { dismiss() }) {
          Image(systemName: "chevron.left")
            .font(.title3.weight(.semibold))
            .foregroundColor(.white)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("Registration")
    // Route anglers to the new screen
    .fullScreenCover(isPresented: $showAnglerLanding) {
      AnglerLandingView()
        .preferredColorScheme(.dark)
    }
    // Scan flow
    .confirmationDialog(
      "Scan Fishing License",
      isPresented: $showScanChoice,
      titleVisibility: .visible
    ) {
      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        Button("Camera") { showScanCamera = true }
      }
      Button("Photo Library") { showScanLibrary = true }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(isPresented: $showScanCamera) {
      ImagePicker(source: .camera) { picked in
        handleScannedImage(picked.image)
      }
    }
    .sheet(isPresented: $showScanLibrary) {
      ImagePicker(source: .library) { picked in
        handleScannedImage(picked.image)
      }
    }
    // Terms sheet
    .sheet(isPresented: $showTermsSheet) {
      TermsAndConditionsView(
        title: termsTitle,
        bodyText: termsBodyText
      )
      .preferredColorScheme(.dark)
    }
  }

  // MARK: - Composed subviews

  @ViewBuilder
  private var mainContent: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        registrationForm
        errorView
      }
      .padding(.top, 8)

      Spacer(minLength: 0)

      registerButtonBar
    }
  }

  // Header removed per design — no logo/branding

  // Whole form stack
  @ViewBuilder
  private var registrationForm: some View {
    VStack(spacing: 10) {
      rolePicker
      nameFields
      anglerNumberFieldIfNeeded
      emailField
      passwordFields
      termsBlock
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var rolePicker: some View {
    HStack(spacing: 0) {
      roleTab("Guide", type: .guide)
      roleTab("Angler", type: .angler)
    }
    .background(Color.white.opacity(0.08))
    .cornerRadius(10)
  }

  private func roleTab(_ label: String, type: AuthService.UserType) -> some View {
    Button {
      if userType != type {
        userType = type
        resetFormForRoleChange()
      }
    } label: {
      Text(label)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(userType == type ? Color.blue : Color.clear)
        .foregroundColor(userType == type ? .white : .gray)
        .cornerRadius(10)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var communityPickerRow: some View {
    HStack(spacing: 8) {
      Text("Select community")
        .font(.body)
        .foregroundColor(.gray)
        .frame(maxWidth: .infinity, alignment: .trailing)

      fieldBackground(
        Picker("Select community", selection: $selectedCommunity) {
          ForEach(Community.allCases) { community in
            Text(community.rawValue).tag(community)
          }
        }
        .pickerStyle(.menu)
        .font(.body)
        .accentColor(.white)
      )
      .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("communityPicker_registration")
  }

  @ViewBuilder
  private var scanButtonIfNeeded: some View {
    if userType == .angler {
      Button {
        showScanChoice = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "text.viewfinder")
          Text("Scan Fishing License")
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .padding(.top, 8)
      .accessibilityIdentifier("scanLicenseButton_registration")
    }
  }

  @ViewBuilder
  private var nameFields: some View {
    HStack(spacing: 8) {
      fieldBackground(
        TextField("First name", text: $firstName)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
      )

      fieldBackground(
        TextField("Last name", text: $lastName)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
      )
    }
  }

  @ViewBuilder
  private var anglerNumberFieldIfNeeded: some View {
    if userType == .angler {
      fieldBackground(
        TextField("ODFW ID", text: $anglerNumber)
          .keyboardType(.numberPad)
          .textInputAutocapitalization(.never)
          .accessibilityIdentifier("anglerNumber_registration")
      )
    }
  }

  @ViewBuilder
  private var emailField: some View {
    fieldBackground(
      TextField("Email", text: $email)
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled(true)
        .disableAutocorrection(true)
        .textContentType(.none)
        .privacySensitive()
        .submitLabel(.next)
    )

    // Email validation indicator
    if !email.isEmpty {
      HStack(spacing: 4) {
        Image(systemName: isEmailValid ? "checkmark.circle.fill" : "xmark.circle.fill")
          .font(.caption2)
          .foregroundColor(isEmailValid ? .green : .red)
        Text(isEmailValid ? "Valid email" : "Enter a valid email address")
          .font(.caption2)
          .foregroundColor(isEmailValid ? .green : .red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
  }

  @ViewBuilder
  private var passwordFields: some View {
    fieldBackground(
      SecureField("Password", text: $password)
        .textContentType(.none)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .keyboardType(.default)
        .disableAutocorrection(true)
    )

    // Password requirements — always visible
    VStack(alignment: .leading, spacing: 2) {
      Text("Password must contain:")
        .font(.caption2)
        .foregroundColor(.gray)
      passwordRequirement("At least 8 characters", met: hasMinLength)
      passwordRequirement("One uppercase letter", met: hasUppercase)
      passwordRequirement("One lowercase letter", met: hasLowercase)
      passwordRequirement("One number", met: hasNumber)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 4)

    fieldBackground(
      SecureField("Confirm password", text: $confirm)
        .textContentType(.none)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .keyboardType(.default)
        .disableAutocorrection(true)
        .privacySensitive()
    )

    // Confirm password match indicator
    if !confirm.isEmpty {
      HStack(spacing: 4) {
        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
          .font(.caption2)
          .foregroundColor(passwordsMatch ? .green : .red)
        Text(passwordsMatch ? "Passwords match" : "Passwords do not match")
          .font(.caption2)
          .foregroundColor(passwordsMatch ? .green : .red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
  }

  private func passwordRequirement(_ text: String, met: Bool) -> some View {
    HStack(spacing: 4) {
      Image(systemName: met ? "checkmark.circle.fill" : "")
        .font(.caption2)
        .foregroundColor(.green)
        .frame(width: 12)
      Text(text)
        .font(.caption2)
        .foregroundColor(met ? .green : .gray)
    }
  }

  @ViewBuilder
  private var termsBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 8) {
        Button {
          hasAgreedToTerms.toggle()
        } label: {
          Image(systemName: hasAgreedToTerms ? "checkmark.square.fill" : "square")
            .font(.title3.weight(.semibold))
            .foregroundColor(hasAgreedToTerms ? .blue : .white)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 4) {
          Text(
            "By checking this box, I agree to the \(userType == .guide ? "guide" : "angler") terms & conditions."
          )
          .font(.footnote)
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)

          Button {
            showTermsSheet = true
          } label: {
            Text("View \(termsTitle)")
              .font(.footnote.weight(.semibold))
              .underline()
              .foregroundColor(.blue)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.top, 2)
  }

  @ViewBuilder
  private var errorView: some View {
    if let err = errorText {
      Text(err)
        .foregroundColor(.red)
        .font(.footnote)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
  }

  @ViewBuilder
  private var registerButtonBar: some View {
    VStack {
      Button {
        Task { await createAccountTapped() }
      } label: {
        HStack {
          if isBusy { ProgressView() }
          Text(isBusy ? "Registering…" : "Register")
            .font(.headline.bold())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(canRegister ? Color.blue : Color.blue.opacity(0.4))
        )
        .foregroundColor(.white)
        .padding(.horizontal)
      }
      .disabled(!canRegister)
      .padding(.top, 4)
      .padding(.bottom, 10)
    }
    .background(Color.black.ignoresSafeArea(edges: .bottom))
  }

  // MARK: - Actions

  private func createAccountTapped() async {
    guard hasAgreedToTerms else {
      errorText = "Please agree to the Terms and Conditions before registering."
      return
    }

    guard !email.isEmpty, !password.isEmpty else {
      errorText = "Please enter email and password."
      return
    }
    guard password == confirm else {
      errorText = "Passwords don’t match."
      return
    }

    let communityName = selectedCommunity.rawValue

    if userType == .guide {
      // GUIDE REGISTRATION FLOW
      guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        errorText = "Please enter your first name."
        return
      }
      guard !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        errorText = "Please enter your last name."
        return
      }

      errorText = nil
      isBusy = true
      do {
        try await auth.signUp(
          email: email.trimmingCharacters(in: .whitespaces),
          password: password,
          firstName: firstName,
          lastName: lastName,
          userType: userType,
          community: communityName,
          anglerNumber: nil
        )
        // ✅ For guides: just dismiss. AppRootView + LandingView handle onboarding + navigation.
        dismiss()
      } catch {
        errorText = error.localizedDescription
      }
      isBusy = false
      return
    }

    // ANGLER REGISTRATION FLOW
    let trimmedAngler = anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      errorText = "Enter your first and last name, or scan your license."
      return
    }
    let isAnglerValid = trimmedAngler.range(of: #"^\d{5,10}$"#, options: .regularExpression) != nil
    guard isAnglerValid else {
      errorText = "Angler number must be 5–10 digits."
      return
    }

    errorText = nil
    isBusy = true
    do {
      try await supabaseSignUpAngler(
        email: email.trimmingCharacters(in: .whitespaces),
        password: password,
        firstName: firstName,
        lastName: lastName,
        community: communityName,
        anglerNumber: trimmedAngler,
        dob: scannedDOB,
        sex: scannedSex,
        mailingAddress: scannedMailingAddress,
        telephone: scannedTelephone,
        residency: scannedResidency
      )
      try await auth.signIn(
        email: email.trimmingCharacters(in: .whitespaces),
        password: password
      )
      showAnglerLanding = true
    } catch {
      errorText = error.localizedDescription
    }
    isBusy = false
  }

  // MARK: - Supabase Signup (Anglers only)

  private func supabaseSignUpAngler(
    email: String,
    password: String,
    firstName: String,
    lastName: String,
    community: String,
    anglerNumber: String,
    dob: Date?,
    sex: Sex?,
    mailingAddress: String?,
    telephone: String?,
    residency: Residency?
  ) async throws {
    var request = URLRequest(url: supabaseSignupURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

    var dataPayload: [String: Any] = [
      "first_name": firstName,
      "last_name": lastName,
      "user_type": "angler",
      "community": community,
      "angler_number": anglerNumber
    ]

    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd"
    if let d = dob { dataPayload["date_of_birth"] = df.string(from: d) }
    if let s = sex { dataPayload["sex"] = s.rawValue }
    if let addr = mailingAddress, !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      dataPayload["mailing_address"] = addr
    }
    if let tel = telephone, !tel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      dataPayload["telephone_number"] = tel
    }
    if let res = residency { dataPayload["residency"] = res.rawValue }

    let body: [String: Any] = ["email": email, "password": password, "data": dataPayload]
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(domain: "Signup", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from server."])
    }
    guard (200 ... 299).contains(http.statusCode) else {
      if let msg = parseErrorMessage(from: data), !msg.isEmpty {
        throw NSError(domain: "Signup", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
      }
      throw NSError(
        domain: "Signup",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "Signup failed with status \(http.statusCode)."]
      )
    }
  }

  private func parseErrorMessage(from data: Data) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let msg = obj["msg"] as? String { return msg }
    if let error = obj["error_description"] as? String { return error }
    if let err = obj["error"] as? String { return err }
    if let m = obj["message"] as? String { return m }
    return nil
  }

  // MARK: - OCR handling

  private func handleScannedImage(_ image: UIImage?) {
    guard userType == .angler, let img = image else { return }

    let opts = FSELicenseTextRecognizer.Options(
      recognitionLanguages: ["en-CA", "en-US"],
      region: .bcNonTidal
    )

    FSELicenseTextRecognizer.recognize(in: img, options: opts) { result in
      var didFill = false

      if let lic = result.licenseNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !lic.isEmpty {
        anglerNumber = lic
        didFill = true
      }
      if let name = result.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        let parts = splitName(name)
        firstName = parts.first
        lastName = parts.last
        didFill = true
      }

      let ocrDOBString = result.dobISO8601
      let ocrTelephone = result.telephone
      let ocrResidencyString = result.residency

      if let dobStr = ocrDOBString {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        scannedDOB = df.date(from: dobStr)
      }

      if let tel = ocrTelephone, !tel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        scannedTelephone = tel
      }

      if let res = ocrResidencyString?.lowercased() {
        switch res {
        case "b.c. resident", "bc resident", "british columbia resident":
          scannedResidency = .CA
        case "not a canadian resident":
          scannedResidency = .US
        default:
          scannedResidency = .other
        }
      }

      scannedSex = nil
      scannedMailingAddress = nil

      if !didFill {
        errorText = "Couldn't read name or angler number. Try a clearer photo."
      } else if errorText?.isEmpty == false {
        errorText = nil
      }
    }
  }

  private func splitName(_ full: String) -> (first: String, last: String) {
    let t = full.trimmingCharacters(in: .whitespacesAndNewlines)
    if let comma = t.firstIndex(of: ",") {
      let last = t[..<comma].trimmingCharacters(in: .whitespaces)
      let first = t[t.index(after: comma)...].trimmingCharacters(in: .whitespaces)
      return (first, last)
    }
    let parts = t.split(separator: " ").map(String.init)
    guard parts.count >= 2 else { return (t, "") }
    return (parts.first ?? "", parts.dropFirst().joined(separator: " "))
  }

  // MARK: - Reset on role toggle

  private func resetFormForRoleChange() {
    firstName = ""
    lastName = ""
    anglerNumber = ""
    email = ""
    password = ""
    confirm = ""

    scannedDOB = nil
    scannedSex = nil
    scannedMailingAddress = nil
    scannedTelephone = nil
    scannedResidency = nil

    hasAgreedToTerms = false
    errorText = nil

    showScanChoice = false
    showScanCamera = false
    showScanLibrary = false

    // Reset community to default when switching roles
    selectedCommunity = .bendFlyShop
  }
}
