import Foundation

/// Mode for the Add Shift view
/// - single: Add one or more individual shifts on specific dates
/// - recurring: Create a recurring shift pattern
/// - events: Add a private calendar event
enum AddShiftMode: String, CaseIterable, Identifiable, Codable {
  case single
  case events
  case recurring

  var id: String { rawValue }

  static let displayOrder: [AddShiftMode] = [.single, .events, .recurring]

  /// Localization key for the mode title
  var titleKey: LocalizedStringResource {
    switch self {
    case .single:
      return .addShiftModeSingle
    case .recurring:
      return .addShiftModeRecurring
    case .events:
      return .addShiftModeEvents
    }
  }

  var nextMode: AddShiftMode {
    guard let currentIndex = Self.displayOrder.firstIndex(of: self) else {
      return .single
    }

    let nextIndex = Self.displayOrder.index(after: currentIndex)
    if nextIndex == Self.displayOrder.endIndex {
      return Self.displayOrder[Self.displayOrder.startIndex]
    }

    return Self.displayOrder[nextIndex]
  }
}
