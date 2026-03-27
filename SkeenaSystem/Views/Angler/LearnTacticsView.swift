// Bend Fly Shop

import SwiftUI
import WebKit

struct LearnTacticsView: View {
  @EnvironmentObject private var communityService: CommunityService

  @Environment(\.dismiss) private var dismiss
  @Environment(\.navigateTo) private var navigateTo

  private var lessonsURL: URL {
    URL(string: communityService.activeCommunityConfig.resolvedLearnUrl)
      ?? URL(string: AppEnvironment.shared.defaultLearnURL)!
  }

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
      ToolbarTab(icon: "message", label: "Social") {
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

  func makeCoordinator() -> Coordinator { Coordinator() }

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
    webView.navigationDelegate = context.coordinator
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    // Only load if not already at the target URL
    if webView.url == nil || webView.url?.absoluteString != url.absoluteString {
      print("[WebView] Loading URL: \(url.absoluteString)")
      webView.load(URLRequest(url: url))
    }
  }

  class Coordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      print("[WebView] Started loading: \(webView.url?.absoluteString ?? "<nil>")")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      print("[WebView] Finished loading: \(webView.url?.absoluteString ?? "<nil>")")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      print("[WebView][ERROR] Navigation failed: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      print("[WebView][ERROR] Provisional navigation failed: \(error.localizedDescription)")
    }
  }
}
