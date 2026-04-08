import Foundation

enum TermsRole: String {
  case guide
  case angler
}

enum TermsStore {
  static func title(for role: TermsRole) -> String {
    switch role {
    case .guide:  return "Guide Terms & Conditions"
    case .angler: return "Angler Terms & Conditions"
    }
  }

  static func bodyText(for role: TermsRole) -> String {
    let filename: String
    switch role {
    case .guide:  filename = "guide_terms"
    case .angler: filename = "angler_terms"
    }

    // Change "md" to "txt" if you prefer plain text files
    guard let url = Bundle.main.url(forResource: filename, withExtension: "md") else {
      return "Terms file missing: \(filename).md"
    }

    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      return "Unable to load Terms (\(filename).md): \(error.localizedDescription)"
    }
  }
}
