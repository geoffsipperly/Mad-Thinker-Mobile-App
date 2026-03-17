// Bend Fly Shop

import SwiftUI

struct AppRootView: View {
  @StateObject private var auth = AuthService.shared

  /// Whether the splash has played (scope depends on frequency mode).
  @State private var splashCompleted = false
  /// The randomly selected video URL (nil when no videos are available).
  @State private var splashVideoURL: URL?
  /// Tracks whether the user was previously authenticated, so we can
  /// detect fresh logins as well as already-authenticated launches.
  @State private var wasAuthenticated = false

  /// UserDefaults key used by the FIRST_LOGIN frequency mode.
  private static let firstLoginSplashKey = "hasShownSplashVideo"

  var body: some View {
    Group {
      if auth.isAuthenticated {
        if !splashCompleted, let videoURL = splashVideoURL {
          SplashVideoView(videoURL: videoURL) {
            markSplashComplete()
          }
        } else {
          switch auth.currentUserType ?? AuthService.UserType.guide {
          case .guide:
            LandingView()
          case .angler:
            AnglerLandingView()
          }
        }
      } else {
        LoginView()
      }
    }
    .task {
      // Optional: warm up cached JWT for your uploader on launch
      await AuthStore.shared.refreshFromSupabase()
      // Make sure we know the role after launch/sign-in/refresh
      await auth.loadUserProfile()

      // After profile loads, if already authenticated (cached session)
      // prepare the splash now — onChange won't fire for the initial value.
      if auth.isAuthenticated && !wasAuthenticated {
        wasAuthenticated = true
        prepareSplashIfNeeded()
      }
    }
    .onChange(of: auth.isAuthenticated) { new in
      AppLogging.log("[AppRootView] isAuthenticated -> \(new)", level: .debug, category: .auth)

      if new && !wasAuthenticated {
        print("[AppRootView] onChange isAuthenticated -> true (login detected)")
        wasAuthenticated = true
        prepareSplashIfNeeded()
      } else if !new {
        wasAuthenticated = false
      }
    }
    .onChange(of: auth.currentUserType) { new in
      AppLogging.log("[AppRootView] currentUserType -> \(String(describing: new))", level: .debug, category: .auth)
    }

  }

  // MARK: - Splash frequency logic

  private func prepareSplashIfNeeded() {
    let frequency = AppEnvironment.shared.splashVideoFrequency

    switch frequency {
    case .always:
      // Reset each login so the video always plays
      splashCompleted = false

    case .firstLogin:
      if UserDefaults.standard.bool(forKey: Self.firstLoginSplashKey) {
        splashCompleted = true
        return
      }

    case .session:
      // splashCompleted is @State — already false on fresh launch,
      // stays true if user signs out and back in during the same session.
      if splashCompleted { return }
    }

    splashVideoURL = SplashVideoManager.randomVideo()
    if splashVideoURL == nil {
      splashCompleted = true
    }
    let willRunSplash = (splashVideoURL != nil) && !splashCompleted
    AppLogging.log(
      "[AppRootView] Splash decision — willRun: \(willRunSplash), frequency: \(AppEnvironment.shared.splashVideoFrequency), videoURL: \(String(describing: splashVideoURL))",
      level: .info,
      category: .auth
    )
  }

  private func markSplashComplete() {
    withAnimation { splashCompleted = true }

    if AppEnvironment.shared.splashVideoFrequency == .firstLogin {
      UserDefaults.standard.set(true, forKey: Self.firstLoginSplashKey)
    }
  }
}
