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

  /// UserDefaults for the shared container, or nil if the App Group container isn't available.
  static func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil else {
      return nil
    }
    return UserDefaults(suiteName: id)
  }
}
