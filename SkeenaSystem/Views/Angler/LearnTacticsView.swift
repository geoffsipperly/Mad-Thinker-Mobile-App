// Bend Fly Shop

import SwiftUI
import WebKit

struct LearnTacticsView: View {
  private let lessonsURL = URL(string: "https://howtoflyfish.orvis.com/video-lessons")!

  @Environment(\.dismiss) private var dismiss
  @Environment(\.navigateTo) private var navigateTo

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      ToolbarTab(icon: "house", label: "Home") {
        navigateTo(nil)
      }
      ToolbarTab(icon: "suitcase", label: "My Trip") {
        navigateTo(.trip)
      }
      ToolbarTab(icon: "cloud.sun", label: "Conditions") {
        navigateTo(.conditions)
      }
      ToolbarTab(icon: "book", label: "Learn") {
        // Already on Learn — no-op
      }
      ToolbarTab(icon: "bubble.left.and.bubble.right", label: "Community") {
        navigateTo(.community)
      }
    }) {
      WebView(url: lessonsURL)
        .ignoresSafeArea(edges: .bottom)
    }
    .navigationTitle("Learn new tactics")
    .navigationBarBackButtonHidden(true)
  }
}

// MARK: - Simple WKWebView wrapper

struct WebView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> WKWebView {
    let prefs = WKWebpagePreferences()
    prefs.allowsContentJavaScript = true

    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences = prefs
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = [] // allow autoplay where possible

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.backgroundColor = .black
    webView.scrollView.backgroundColor = .black
    webView.scrollView.indicatorStyle = .white
    webView.isOpaque = false
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    // Only load if not already at the target URL
    if webView.url == nil || webView.url?.absoluteString != url.absoluteString {
      webView.load(URLRequest(url: url))
    }
  }
}
