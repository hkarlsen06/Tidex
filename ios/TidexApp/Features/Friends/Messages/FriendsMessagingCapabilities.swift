import Foundation

protocol FriendsMessagingCapabilityProviding {
  var canSendShiftSnapshots: Bool { get }
}

struct FriendsMessagingCapabilities: FriendsMessagingCapabilityProviding {
  // swiftlint:disable:next explicit_acl explicit_type_interface
  static let shared = Self()

  var canSendShiftSnapshots: Bool { true }
}
