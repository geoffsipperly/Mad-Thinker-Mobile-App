// Bend Fly Shop
//
// CatchCaptureContext.swift — lightweight context bag for guide / client /
// license / location state that `ReportChatView` seeds before starting the
// catch chat. Replaces the old `ReportFormViewModel`, which was a remnant of
// a deleted form-based save path that used to write directly to Core Data.
//
// Kept as an `ObservableObject` only so SwiftUI views can bind text fields
// and `@StateObject` it. No save logic, no validation — all of that lives
// in `CatchChatViewModel` + `CatchReportStore` now.

import Combine
import CoreLocation
import Foundation

final class CatchCaptureContext: ObservableObject {
  /// Logged-in guide's first name, seeded from `AuthService.shared.currentFirstName`
  /// in `ReportChatView.handleOnAppear`. Passed through to the chat VM as the
  /// `guideName` context for assistant prompts.
  @Published var guideName: String = ""

  /// Angler's display name (or the guide's own name in solo mode). Updated
  /// whenever the client picker selection changes.
  @Published var clientName: String = ""

  /// Angler's MAD member number. REQUIRED on the v5 upload payload — the
  /// chat save path reads this from `vm.memberId` when building the snapshot.
  @Published var memberId: String = ""

  /// Optional BC classified-waters licence number. Hidden behind the
  /// `E_MANAGE_LICENSES` feature flag. Persisted on the local `CatchReport`
  /// for display in the detail view; no longer uploaded (v5 dropped it).
  @Published var classifiedWatersLicenseNumber: String?

  /// Latest device location, pushed in from the `LocationManager` publisher
  /// inside `ReportChatView`. Forwarded to `CatchChatViewModel.updateLocation`
  /// so photo analysis can pick a river from GPS when EXIF is missing.
  var currentLocation: CLLocation?
}
