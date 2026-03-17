import Foundation

extension Notification.Name {
  /// Posted when a trip or its child entities (angler / license) are changed
  /// and saved locally. TripListView listens for this so it can refresh the list.
  static let tripDidChange = Notification.Name("TripDidChangeNotification")
}
