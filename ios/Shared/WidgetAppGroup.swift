import Foundation

/// App Group id and UserDefaults keys shared by the main app's widget storage writer
/// (`NativeWidgetStorage`) and the widget extension's timeline providers, so both sides
/// read and write the same UserDefaults suite and keys.
enum WidgetAppGroup {
  static let id = "group.no.tidex.app"

  static let shiftsKey = "upcoming_shifts"
  static let currencyKey = "user_currency"
  static let friendSharersKey = "friend_sharers"
  static let friendShiftsKey = "friend_shifts"
  static let monthlyTotalsKey = "monthly_totals"
  /// The signed-in Tidex user id, lowercased. The notification service extension compares it
  /// with `recipient_user_id` in each push. The app writes it at sign-in and removes it at
  /// sign-out. `TidexNotificationService` repeats this key, because it doesn't compile this file.
  static let signedInUserIdKey = "signed_in_user_id"

  /// UserDefaults for the shared container, or nil if the App Group container isn't available.
  static func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil else {
      return nil
    }
    return UserDefaults(suiteName: id)
  }

  /// Stores the signed-in user id for the notification service extension, or clears it with nil.
  static func storeSignedInUserId(_ userId: String?) {
    guard let defaults = sharedUserDefaults() else { return }
    if let userId {
      defaults.set(userId.lowercased(), forKey: signedInUserIdKey)
    } else {
      defaults.removeObject(forKey: signedInUserIdKey)
    }
  }
}
