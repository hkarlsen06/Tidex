import Foundation

/// Mode for the Add Shift view
/// - single: Add one or more individual shifts on specific dates
/// - recurring: Create a recurring shift pattern
/// - events: Add a private calendar event
internal enum AddShiftMode: CaseIterable, Identifiable, Codable, RawRepresentable {
  case events
  case recurring
  case single

  internal init?(rawValue: String) {
    switch rawValue {
    case "events":
      self = .events

    case "recurring":
      self = .recurring

    case "single":
      self = .single

    default:
      return nil
    }
  }

  internal static let displayOrder: [Self] = [.single, .events, .recurring]

  internal var rawValue: String {
    switch self {
    case .events:
      return "events"

    case .recurring:
      return "recurring"

    case .single:
      return "single"
    }
  }

  internal var id: String { rawValue }

  /// Localization key for the mode title
  internal var titleKey: LocalizedStringResource {
    switch self {
    case .events:
      return .addShiftModeEvents

    case .recurring:
      return .addShiftModeRecurring

    case .single:
      return .addShiftModeSingle
    }
  }

  internal var nextMode: Self {
    guard let currentIndex = Self.displayOrder.firstIndex(of: self) else {
      return .single
    }

    let nextIndex: [Self].Index = Self.displayOrder.index(after: currentIndex)
    if nextIndex == Self.displayOrder.endIndex {
      return Self.displayOrder[Self.displayOrder.startIndex]
    }

    return Self.displayOrder[nextIndex]
  }
}
