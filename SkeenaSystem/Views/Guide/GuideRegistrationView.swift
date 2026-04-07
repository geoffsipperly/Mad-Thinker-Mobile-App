// Bend Fly Shop

import SwiftUI
import UIKit

struct GuideRegistrationView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var auth = AuthService.shared
  @StateObject private var communityService = CommunityService.shared

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

  @State private var email: String = ""
  @State private var password: String = ""
  @State private var confirm: String = ""

  // MARK: - Hidden fields populated by scan (sent to API if available)

  enum Sex: String, CaseIterable, Identifiable { case male, female, other; var id: String { rawValue } }
  enum Residency: String, CaseIterable, Identifiable { case US, CA, other; var id: String { rawValue } }

  @State private var telephoneNumber: String = ""

  // MARK: - UI state

  @State private var isBusy = false
  @State private var errorText: String?
  @State private var showAnglerLanding = false


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
    // Community code is optional for full registration (Path C)
    let codeOK = communityCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommunityCodeValid
    return base && codeOK
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
      nameFields
      telephoneField
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

  // License number and license fields removed — member_id is auto-generated on backend.

  @ViewBuilder
  private var telephoneField: some View {
    fieldBackground(
      TextField("Phone Number", text: $telephoneNumber)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
        .autocorrectionDisabled(true)
        .submitLabel(.next)
    )
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

    guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorText = "Please enter your first name."
      return
    }
    guard !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorText = "Please enter your last name."
      return
    }
    // Community code is optional for Path C; validate only if provided
    if !code.isEmpty {
      guard isCommunityCodeValid else {
        errorText = "Please enter a valid 6-character community code."
        return
      }
    }

    errorText = nil
    isBusy = true

    if userType == .guide {
      // GUIDE REGISTRATION FLOW
      do {
        try await auth.signUp(
          email: email.trimmingCharacters(in: .whitespaces),
          password: password,
          firstName: firstName,
          lastName: lastName,
          userType: userType,
          communityCode: code.isEmpty ? nil : code
        )
        dismiss()
      } catch {
        errorText = error.localizedDescription
      }
      isBusy = false
      return
    }

    // ANGLER REGISTRATION FLOW — member_id auto-generated on backend
    do {
      try await supabaseSignUpAngler(
        email: email.trimmingCharacters(in: .whitespaces),
        password: password,
        firstName: firstName,
        lastName: lastName,
        communityCode: code.isEmpty ? nil : code,
        dob: nil,
        sex: nil,
        mailingAddress: nil,
        telephone: telephoneNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : telephoneNumber.trimmingCharacters(in: .whitespaces),
        residency: nil
      )
      try await auth.signIn(
        email: email.trimmingCharacters(in: .whitespaces),
        password: password
      )
      AppLogging.log("[GuideRegistration] signIn complete — isAuthenticated=\(auth.isAuthenticated)", level: .info, category: .auth)

      // Fetch memberships now so the community is auto-selected before the
      // landing view appears. Without this, checkOnboarding() in
      // AnglerLandingView fires before activeCommunityTypeName is set.
      await communityService.fetchMemberships()
      AppLogging.log("[GuideRegistration] fetchMemberships complete — activeCommunityId=\(communityService.activeCommunityId ?? "nil") typeName=\(communityService.activeCommunityTypeName ?? "nil") memberships=\(communityService.memberships.count)", level: .info, category: .auth)

      showAnglerLanding = true
      AppLogging.log("[GuideRegistration] showAnglerLanding = true", level: .info, category: .auth)
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
    communityCode: String?,
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
      "user_type": "angler"
    ]
    if let code = communityCode, !code.isEmpty { dataPayload["community_code"] = code }

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


  // MARK: - Reset helpers

  private func resetFormForRoleChange() {
    firstName = ""
    lastName = ""
    email = ""
    password = ""
    confirm = ""

    hasAgreedToTerms = false
    errorText = nil

    communityCode = ""
  }

  private func resetAllFields() {
    resetFormForRoleChange()
    userType = .guide
  }
}
