import Foundation

// MARK: - Friend Section Type

/// Which way shifts are shared between the viewer and a friend
enum FriendSectionType {
  case mutual  // Both share with each other
  case outgoing  // Only I share with them
  case incoming  // Only they share with me
}

enum FriendSharingRemovalAction: CaseIterable, Hashable {
  case stopSharingMyShifts
  case stopSeeingTheirShifts

  // swiftlint:disable:next explicit_acl type_contents_order
  static func availableActions(for sectionType: FriendSectionType) -> [Self] {
    switch sectionType {
    case .mutual:
      return [.stopSharingMyShifts, .stopSeeingTheirShifts]

    case .outgoing:
      return [.stopSharingMyShifts]

    case .incoming:
      return [.stopSeeingTheirShifts]
    }
  }

  var title: String {
    switch self {
    case .stopSharingMyShifts:
      return String(localized: .sharingActionStopSharingMyShifts)

    case .stopSeeingTheirShifts:
      return String(localized: .sharingActionStopSeeingTheirShifts)
    }
  }

  var systemImage: String {
    switch self {
    case .stopSharingMyShifts:
      return "person.crop.circle.badge.minus"

    case .stopSeeingTheirShifts:
      return "eye.slash"
    }
  }

  func confirmationTitle(friendName: String) -> String {
    switch self {
    case .stopSharingMyShifts:
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.title", friendName)

    case .stopSeeingTheirShifts:
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.title", friendName)
    }
  }

  func confirmationMessage(friendName: String, sectionType: FriendSectionType) -> String {
    switch (self, sectionType) {
    case (.stopSharingMyShifts, .mutual):
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.mutual", friendName)

    case (.stopSharingMyShifts, .outgoing):
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.outgoingOnly", friendName)

    case (.stopSeeingTheirShifts, .mutual):
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.mutual", friendName)

    case (.stopSeeingTheirShifts, .incoming):
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.incomingOnly", friendName)

    case (.stopSharingMyShifts, .incoming), (.stopSeeingTheirShifts, .outgoing):
      return confirmationTitle(friendName: friendName)
    }
  }

  static func localizedFormat(_ key: String, _ argument: String) -> String {
    let format = String(localized: String.LocalizationValue(key), table: "Localizable")
    return String.localizedStringWithFormat(format, argument)
  }
}
