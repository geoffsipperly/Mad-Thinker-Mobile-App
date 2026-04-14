// Bend Fly Shop

import Combine
import Foundation

/// Per-device preference for whether a guide opts their catches into the
/// conservation (research-grade) flow instead of the standard guide flow.
///
/// Persisted in `UserDefaults` so the toggle survives app launches.
/// Read from `GuideLandingView` (the toggle UI) and from `ReportChatView`
/// (seeds `CatchChatViewModel.conservationMode` before the chat begins).
///
/// Singleton pattern mirrors `AuthService.shared` / `CatchReportStore.shared`.
public final class ConservationModeStore: ObservableObject {

  // MARK: - Shared instance

  public static let shared = ConservationModeStore()

  // MARK: - Storage key

  /// UserDefaults key. Guide-scoped today; may become community-scoped later.
  internal static let defaultsKey = "guide.conservationMode.enabled"

  // MARK: - State

  /// Whether the guide has opted every catch into the conservation flow.
  /// Writes are synchronously persisted to `UserDefaults`.
  @Published public var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
    }
  }

  // MARK: - Init

  private init() {
    // `UserDefaults.bool(forKey:)` returns `false` when the key is absent,
    // which matches the documented default.
    self.isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
  }

  // MARK: - Test helpers

  /// Reset to factory default. Tests should call this in setUp/tearDown so
  /// stale state does not leak between cases.
  ///
  /// Order matters: we must assign `isEnabled = false` FIRST (triggering
  /// `didSet`, which writes `false` into UserDefaults) and only THEN remove
  /// the key. Removing first would let the subsequent `didSet` re-create the
  /// key with value `0`, leaving the store not truly "factory default".
  public func resetForTests() {
    isEnabled = false
    UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
  }
}
