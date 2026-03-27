// Bend Fly Shop

import SwiftUI
import UIKit

struct GuideRegistrationView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared

  // MARK: - Community Code

  // MARK: - Constants

  private let supabaseSignupURL = AppEnvironment.shared.projectURL.appendingPathComponent("/auth/v1/signup")
  private let supabaseAnonKey = AppEnvironment.shared.anonKey

  // MARK: - Registration path

  /// nil = choice screen, true = invite path, false = full registration
  @State private var hasCommunityCode: Bool?

  // MARK: - Form fields

  @State private var userType: AuthService.UserType = .guide
  @State private var communityCode: String = ""

  @State private var firstName: String = ""
  @State private var lastName: String = ""
  @State private var anglerNumber: String = ""

  @State private var email: String = ""
  @State private var password: String = ""
  @State private var confirm: String = ""

  // MARK: - License fields (both guides and anglers)

  @State private var licenseCountry: LicenseCountry = .US
  @State private var licenseStateProvince: String = ""
  @State private var licenseExpirationDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

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

  private var isCommunityCodeValid: Bool {
    let code = communityCode.trimmingCharacters(in: .whitespacesAndNewlines)
    return code.range(of: #"^[A-Za-z0-9]{6}$"#, options: .regularExpression) != nil
  }

  private var allFieldsFilled: Bool {
    let base = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && isEmailValid
      && isCommunityCodeValid
    if userType == .angler {
      return base && !anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return base
  }

  private var canRegister: Bool {
    !isBusy && hasAgreedToTerms && isPasswordValid && allFieldsFilled
  }

  /// Validation for the invite-based registration path (no name/license required)
  private var canRegisterInvite: Bool {
    !isBusy && hasAgreedToTerms && isPasswordValid && isEmailValid && isCommunityCodeValid
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
        Button(action: {
          if hasCommunityCode != nil {
            // Go back to the choice screen
            hasCommunityCode = nil
            resetAllFields()
          } else {
            dismiss()
          }
        }) {
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
    switch hasCommunityCode {
    case nil:
      communityCodeChoiceScreen
    case true:
      inviteRegistrationContent
    case false:
      fullRegistrationContent
    }
  }

  // MARK: - Choice Screen

  @ViewBuilder
  private var communityCodeChoiceScreen: some View {
    VStack(spacing: 24) {
      Spacer()

      Image("MadThinkerLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16))

      Text("Do you have a community code?")
        .font(.title3.weight(.semibold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)

      Text("If your guide or community admin gave you a code, you can use it to quickly set up your account.")
        .font(.subheadline)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      VStack(spacing: 12) {
        Button {
          hasCommunityCode = true
        } label: {
          HStack {
            Image(systemName: "ticket")
            Text("Yes, I have a code")
          }
          .font(.headline)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
          .foregroundColor(.white)
        }
        .accessibilityIdentifier("hasCodeButton")

        Button {
          hasCommunityCode = false
        } label: {
          HStack {
            Image(systemName: "person.badge.plus")
            Text("No, continue without one")
          }
          .font(.headline)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
          .foregroundColor(.white)
        }
        .accessibilityIdentifier("noCodeButton")
      }
      .padding(.horizontal, 24)

      Spacer()
      Spacer()
    }
  }

  // MARK: - Invite Registration Path

  @ViewBuilder
  private var inviteRegistrationContent: some View {
    VStack(spacing: 0) {
      ScrollView {
        Image("MadThinkerLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 120, height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .padding(.top, 12)
          .padding(.bottom, 4)

        VStack(spacing: 10) {
          inviteRegistrationForm
          errorView
        }
        .padding(.top, 8)
      }

      inviteRegisterButtonBar
    }
  }

  @ViewBuilder
  private var inviteRegistrationForm: some View {
    VStack(spacing: 10) {
      communityCodeField
      emailField
      passwordFields
      inviteTermsBlock
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var inviteTermsBlock: some View {
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
          Text("By checking this box, I agree to the terms & conditions.")
            .font(.footnote)
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)

          Button {
            showTermsSheet = true
          } label: {
            Text("View Terms & Conditions")
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
  private var inviteRegisterButtonBar: some View {
    VStack {
      Button {
        Task { await createInviteAccountTapped() }
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
            .fill(canRegisterInvite ? Color.blue : Color.blue.opacity(0.4))
        )
        .foregroundColor(.white)
        .padding(.horizontal)
      }
      .disabled(!canRegisterInvite)
      .padding(.top, 4)
      .padding(.bottom, 10)
    }
    .background(Color.black.ignoresSafeArea(edges: .bottom))
  }

  // MARK: - Full Registration Path (existing)

  @ViewBuilder
  private var fullRegistrationContent: some View {
    VStack(spacing: 0) {
      ScrollView {
        // Platform branding — MadThinker logo (not community-specific)
        Image("MadThinkerLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 120, height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .padding(.top, 12)
          .padding(.bottom, 4)

        VStack(spacing: 10) {
          registrationForm
          errorView
        }
        .padding(.top, 8)
      }

      registerButtonBar
    }
  }

  // Whole form stack
  @ViewBuilder
  private var registrationForm: some View {
    VStack(spacing: 10) {
      rolePicker
      communityCodeField
      nameFields
      licenseNumberField
      licenseFields
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
  private var communityCodeField: some View {
    fieldBackground(
      TextField("Community Code", text: $communityCode)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .keyboardType(.asciiCapable)
        .accessibilityIdentifier("communityCode_registration")
    )

    if !communityCode.isEmpty {
      HStack(spacing: 4) {
        Image(systemName: isCommunityCodeValid ? "checkmark.circle.fill" : "xmark.circle.fill")
          .font(.caption2)
          .foregroundColor(isCommunityCodeValid ? .green : .red)
        Text(isCommunityCodeValid ? "Valid code format" : "Must be 6 alphanumeric characters")
          .font(.caption2)
          .foregroundColor(isCommunityCodeValid ? .green : .red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
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
  private var licenseNumberField: some View {
    fieldBackground(
      TextField("License Number", text: $anglerNumber)
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.never)
        .accessibilityIdentifier("anglerNumber_registration")
    )
  }

  // MARK: - License Fields (Country, State/Province, Expiration)

  @ViewBuilder
  private var licenseFields: some View {
    VStack(spacing: 8) {
      // Country picker
      HStack {
        Text("License Country")
          .font(.caption)
          .foregroundColor(.gray)
        Spacer()
        Picker("Country", selection: $licenseCountry) {
          ForEach(LicenseCountry.allCases) { country in
            Text(country.displayName).tag(country)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
      }
      .padding(.horizontal, 10)

      // State/Province picker
      HStack {
        Text(licenseCountry.subdivisionLabel)
          .font(.caption)
          .foregroundColor(.gray)
        Spacer()
        Picker(licenseCountry.subdivisionLabel, selection: $licenseStateProvince) {
          Text("Select...").tag("")
          ForEach(licenseCountry.subdivisions, id: \.self) { sub in
            Text(sub).tag(sub)
          }
        }
        .tint(.white)
      }
      .padding(.horizontal, 10)
      .frame(height: 40)
      .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

      // Expiration date
      HStack {
        Text("License Expiration")
          .font(.caption)
          .foregroundColor(.gray)
        Spacer()
        DatePicker("", selection: $licenseExpirationDate, in: Date()..., displayedComponents: .date)
          .labelsHidden()
          .colorScheme(.dark)
      }
      .padding(.horizontal, 10)
      .frame(height: 40)
      .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    .onChange(of: licenseCountry) { _ in
      // Reset state/province when country changes
      licenseStateProvince = ""
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

  /// Invite-based registration (Path A): only community code, email, password
  private func createInviteAccountTapped() async {
    guard hasAgreedToTerms else {
      errorText = "Please agree to the Terms and Conditions before registering."
      return
    }
    guard !email.isEmpty, !password.isEmpty else {
      errorText = "Please enter email and password."
      return
    }
    guard password == confirm else {
      errorText = "Passwords don't match."
      return
    }
    guard isCommunityCodeValid else {
      errorText = "Please enter a valid 6-character community code."
      return
    }

    let code = communityCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    errorText = nil
    isBusy = true
    do {
      try await auth.signUpWithInvite(
        email: email.trimmingCharacters(in: .whitespaces),
        password: password,
        communityCode: code
      )
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
    isBusy = false
  }

  /// Full registration (Path B): all fields required
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
      errorText = "Passwords don't match."
      return
    }

    let code = communityCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

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
      guard isCommunityCodeValid else {
        errorText = "Please enter a valid 6-character community code."
        return
      }

      errorText = nil
      isBusy = true
      do {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        try await auth.signUp(
          email: email.trimmingCharacters(in: .whitespaces),
          password: password,
          firstName: firstName,
          lastName: lastName,
          userType: userType,
          communityCode: code,
          anglerNumber: anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : anglerNumber.trimmingCharacters(in: .whitespacesAndNewlines),
          licenseCountry: licenseCountry.rawValue,
          licenseStateProvince: licenseStateProvince.isEmpty ? nil : licenseStateProvince,
          licenseExpirationDate: df.string(from: licenseExpirationDate)
        )
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
    let isAnglerValid = trimmedAngler.range(of: #"^[A-Za-z0-9\-]{3,20}$"#, options: .regularExpression) != nil
    guard isAnglerValid else {
      errorText = "Angler number must be 3-20 characters (letters, digits, or hyphens)."
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
        communityCode: code,
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
    communityCode: String,
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
      "community_code": communityCode,
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

    // License fields
    dataPayload["license_country"] = licenseCountry.rawValue
    if !licenseStateProvince.isEmpty { dataPayload["license_state_province"] = licenseStateProvince }
    dataPayload["license_expiration_date"] = df.string(from: licenseExpirationDate)

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

  // MARK: - Reset helpers

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

    communityCode = ""
  }

  private func resetAllFields() {
    resetFormForRoleChange()
    userType = .guide
  }
}
