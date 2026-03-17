import SwiftUI

// MARK: - URL composition (consistent with AnglerAboutYou)
private enum StaffDetailAPI {
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

  private static let staffDetailPath: String = {
    (Bundle.main.object(forInfoDictionaryKey: "STAFF_BIO_DETAIL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/functions/v1/staff-bio-detail"
  }()

  static func staffDetailURL(queryItems: [URLQueryItem]) -> URL? {
    guard let base = URL(string: baseURLString), let scheme = base.scheme, let host = base.host else { return nil }
    var comps = URLComponents()
    comps.scheme = scheme
    comps.host = host
    comps.port = base.port

    let basePath = base.path
    let normalizedBasePath = basePath == "/" ? "" : (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath)
    let normalizedPath = staffDetailPath.hasPrefix("/") ? staffDetailPath : "/" + staffDetailPath
    comps.path = normalizedBasePath + normalizedPath
    comps.queryItems = queryItems
    return comps.url
  }
}

struct StaffDetailView: View {
  let community: String
  let lodge: String?
  let firstName: String
  let lastName: String

  @State private var isLoading: Bool = false
  @State private var errorText: String?
  @State private var staff: StaffDetail?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 18) {
        // Header area
        VStack(spacing: 10) {
          if let photoURL = staff?.photo_url, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
              switch phase {
              case .empty:
                ProgressView().tint(.white)
              case .success(let image):
                image.resizable().scaledToFill()
              case .failure:
                Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundColor(.white.opacity(0.6))
              @unknown default:
                Color.white.opacity(0.1)
              }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
          }

          if let s = staff {
            Text("\(s.first_name ?? "") \(s.last_name ?? "")")
              .font(.title2.weight(.semibold))
              .foregroundColor(.white)
            if let role = s.role { Text(role).foregroundColor(.blue) }
            if let lodge = s.lodge, !lodge.isEmpty {
              Text(lodge)
                .font(.subheadline)
                .foregroundColor(.blue)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)

        if let errorText = errorText {
          Text(errorText)
            .font(.footnote)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if isLoading {
              ProgressView().tint(.white)
            }

            if let long = staff?.long_description {
              Text(long)
                .foregroundColor(.white)
                .font(.body)
            }

            if !isLoading && staff == nil && errorText == nil {
              Text("No details available.")
                .foregroundColor(.gray)
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 20)
        }

        Spacer(minLength: 0)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarHidden(false)
    .preferredColorScheme(.dark)
    .task { await fetchDetail() }
  }

  private func fetchDetail() async {
    guard !isLoading else { return }
    errorText = nil
    isLoading = true
    defer { isLoading = false }

    let q: [URLQueryItem] = [
      URLQueryItem(name: "community", value: community),
      URLQueryItem(name: "first_name", value: firstName),
      URLQueryItem(name: "last_name", value: lastName)
    ]
    guard let url = StaffDetailAPI.staffDetailURL(queryItems: q) else {
      errorText = "Invalid URL"
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
#if DEBUG
    AppLogging.log({ "[StaffDetailView] GET \(url.absoluteString)" }, level: .debug, category: .angler)
    let qStr = q.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    AppLogging.log({ "[StaffDetailView] Query: \(qStr)" }, level: .debug, category: .angler)
#endif

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
#if DEBUG
      AppLogging.log({ "[StaffDetailView] Response status: \(code)" }, level: .debug, category: .angler)
      let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      let preview = bodyPreview.count > 2000 ? String(bodyPreview.prefix(2000)) + "\n…(truncated)…" : bodyPreview
      AppLogging.log({ "[StaffDetailView] Body:\n\(preview)" }, level: .debug, category: .angler)
#endif
      guard (200 ..< 300).contains(code) else {
        if code == 404 { errorText = "Staff member not found" } else { errorText = "Fetch failed (\(code))" }
        return
      }

      let decoded = try JSONDecoder().decode(StaffDetailResponse.self, from: data)
      self.staff = decoded.staff
    } catch {
      errorText = "Network error: \(error.localizedDescription)"
    }
  }
}

private struct StaffDetailResponse: Codable {
  let staff: StaffDetail
}

private struct StaffDetail: Codable {
  let first_name: String?
  let last_name: String?
  let role: String?
  let long_description: String?
  let photo_url: String?
  let lodge: String?
}

#Preview {
  NavigationView { StaffDetailView(community: "Westside Anglers", lodge: "River Valley Lodge", firstName: "John", lastName: "Smith") }
}
