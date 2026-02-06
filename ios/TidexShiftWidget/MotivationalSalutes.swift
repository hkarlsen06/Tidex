import Foundation

/// Motivational salute phrases for the shift widget
/// Kept short to fit on one line in the widget
/// Works for shifts today, tomorrow, or in the future
struct MotivationalSalutes {
  /// Returns a random salute using the widget string catalog.
  static func random() -> String {
    let key = LocalizedStringResource.widgetSaluteKeys.randomElement() ?? "salute.01"
    return String(localized: key)
  }

  /// Returns all salutes from the widget string catalog.
  static func all() -> [String] {
    LocalizedStringResource.widgetSaluteKeys.map { String(localized: $0) }
  }
}
