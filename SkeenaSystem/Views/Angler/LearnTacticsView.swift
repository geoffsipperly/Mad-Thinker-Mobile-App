// Bend Fly Shop

import SwiftUI
import WebKit

struct LearnTacticsView: View {
  @EnvironmentObject private var communityService: CommunityService

  @Environment(\.dismiss) private var dismiss

  private var lessonsURL: URL {
    URL(string: communityService.activeCommunityConfig.resolvedLearnUrl)
      ?? URL(string: AppEnvironment.shared.defaultLearnURL)!
  }

  var body: some View {
    DarkPageTemplate(bottomToolbar: {
      RoleAwareToolbar(activeTab: "learn")
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
      AppLogging.log("[WebView] Loading URL: \(url.absoluteString)", level: .debug, category: .ui)
      webView.load(URLRequest(url: url))
    }
  }

  class Coordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      AppLogging.log("[WebView] Started loading: \(webView.url?.absoluteString ?? "<nil>")", level: .debug, category: .ui)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      AppLogging.log("[WebView] Finished loading: \(webView.url?.absoluteString ?? "<nil>")", level: .debug, category: .ui)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      AppLogging.log("[WebView] Navigation failed: \(error.localizedDescription)", level: .error, category: .ui)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      AppLogging.log("[WebView] Provisional navigation failed: \(error.localizedDescription)", level: .error, category: .ui)
    }
  }
}
