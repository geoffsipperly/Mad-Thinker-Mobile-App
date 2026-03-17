import SwiftUI

// MARK: - URL composition (consistent with AnglerAboutYou)
private enum MeetStaffAPI {
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

  private static let staffBiosPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "STAFF_BIOS") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/staff-bios"
  }()

  static func staffBiosURL(queryItems: [URLQueryItem]) -> URL? {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else { return nil }
    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = staffBiosPath.hasPrefix("/") ? staffBiosPath : "/" + staffBiosPath
    comps.path = normalizedBasePath + normalizedPath
    comps.queryItems = queryItems
    return comps.url
  }
}

struct MeetStaff: View {
  @Environment(\.dismiss) private var dismiss

  // Configuration for query params
  private let community: String = AppEnvironment.shared.communityName

  // View state
  @State private var isLoading: Bool = false
  @State private var errorText: String?
  @State private var staff: [StaffMember] = []

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 18) {
        // Top bar (placeholder)
        HStack { Spacer() }
          .padding(.horizontal, 16)
          .padding(.top, 16)

        // Header
        VStack(spacing: 6) {
          Image(AppEnvironment.shared.appLogoAsset)
            .resizable()
            .scaledToFit()
            .frame(width: 130, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 10)
            .padding(.bottom, 2)
        }
        .padding(.bottom, 10)

        // Messages
        if let errorText = errorText {
          Text(errorText)
            .font(.footnote)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }

        // List content
        ScrollView {
          LazyVStack(spacing: 12) {
            if isLoading {
              ProgressView().tint(.white)
            }

            // Group staff by lodge and render sections
            let grouped = Dictionary(grouping: staff, by: { ($0.lodge ?? "Unknown Lodge").trimmingCharacters(in: .whitespacesAndNewlines) })
            let sortedKeys = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            ForEach(sortedKeys, id: \.self) { lodgeName in
              VStack(alignment: .leading, spacing: 8) {
                ForEach(grouped[lodgeName] ?? []) { member in
                  NavigationLink {
                    StaffDetailView(community: community, lodge: member.lodge ?? lodgeName, firstName: member.first_name ?? "", lastName: member.last_name ?? "")
                  } label: {
                    staffRow(member)
                  }
                }
              }
            }

            if !isLoading && staff.isEmpty && errorText == nil {
              Text("No staff found.")
                .foregroundColor(.gray)
                .font(.subheadline)
                .padding(.top, 20)
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 4)
          .padding(.bottom, 20)
        }

        Spacer(minLength: 0)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text("Meet staff")
          .font(.headline)
          .foregroundColor(.white)
      }
    }
    .navigationBarHidden(false)
    .preferredColorScheme(.dark)
    .task { await fetchStaff() }
  }

  // MARK: - Row
  private func staffRow(_ member: StaffMember) -> some View {
    HStack(alignment: .top, spacing: 12) {
      AsyncImage(url: URL(string: member.photo_url ?? "")) { phase in
        switch phase {
        case .empty:
          ZStack { Color.white.opacity(0.1) }
            .overlay(Image(systemName: "person.crop.square").foregroundColor(.white.opacity(0.6)))
        case .success(let image):
          image.resizable().scaledToFill()
        case .failure:
          ZStack { Color.white.opacity(0.1) }
            .overlay(Image(systemName: "person.crop.square").foregroundColor(.white.opacity(0.6)))
        @unknown default:
          Color.white.opacity(0.1)
        }
      }
      .frame(width: 60, height: 60)
      .clipShape(RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 4) {
        Text("\(member.first_name ?? "") \(member.last_name ?? "")")
          .font(.headline)
          .foregroundColor(.white)
        if let role = member.role, !role.isEmpty {
          Text(role)
            .font(.subheadline)
            .foregroundColor(.blue)
        }
        if let desc = member.short_description, !desc.isEmpty {
          Text(desc)
            .font(.footnote)
            .foregroundColor(.white.opacity(0.8))
        }
      }
      .multilineTextAlignment(.leading)
      Spacer()
      Image(systemName: "chevron.right")
        .foregroundColor(.white.opacity(0.6))
        .font(.subheadline.weight(.semibold))
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 16)
    .background(Color.white.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
  }

  // MARK: - Networking
  private func fetchStaff() async {
    guard !isLoading else { return }
    errorText = nil
    isLoading = true
    defer { isLoading = false }

    let q: [URLQueryItem] = [URLQueryItem(name: "community", value: community)]
    guard let url = MeetStaffAPI.staffBiosURL(queryItems: q) else {
      errorText = "Invalid URL"
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"

    #if DEBUG
    AppLogging.log({ "[MeetStaff] GET \(url.absoluteString)" }, level: .debug, category: .angler)
    if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
      let q = items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
      AppLogging.log({ "[MeetStaff] Query: \(q)" }, level: .debug, category: .angler)
    }
    #endif

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

      #if DEBUG
      AppLogging.log({ "[MeetStaff] Response status: \(code)" }, level: .debug, category: .angler)
      let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      let preview = bodyPreview.count > 2000 ? String(bodyPreview.prefix(2000)) + "\n…(truncated)…" : bodyPreview
      AppLogging.log({ "[MeetStaff] Body:\n\(preview)" }, level: .debug, category: .angler)
      #endif

      guard (200 ..< 300).contains(code) else {
        errorText = "Fetch failed (\(code))"
        return
      }

      let decoded = try JSONDecoder().decode(StaffListResponse.self, from: data)
      self.staff = decoded.staff
    } catch {
      errorText = "Network error: \(error.localizedDescription)"
    }
  }
}

// MARK: - Models
private struct StaffListResponse: Codable {
  let staff: [StaffMember]
}

private struct StaffMember: Codable, Identifiable {
  var id: String { (first_name ?? "") + (last_name ?? "") + (role ?? "") + (lodge ?? "") }
  let first_name: String?
  let last_name: String?
  let role: String?
  let short_description: String?
  let photo_url: String?
  let lodge: String?
}

#Preview {
  MeetStaff()
}
