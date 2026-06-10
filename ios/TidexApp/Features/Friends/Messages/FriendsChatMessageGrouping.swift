import Foundation

enum FriendsChatMessageGroupPosition: Equatable {
  case standalone
  case leading
  case middle
  case trailing
}

struct FriendsChatMessageGroupContext: Equatable {
  let position: FriendsChatMessageGroupPosition
  let isCurrentUser: Bool

  // swiftlint:disable:next explicit_acl type_contents_order
  func joiningNext() -> Self {
    let updatedPosition: FriendsChatMessageGroupPosition
    switch position {
    case .standalone:
      updatedPosition = .leading

    case .trailing:
      updatedPosition = .middle

    case .leading, .middle:
      updatedPosition = position
    }

    return Self(
      position: updatedPosition,
      isCurrentUser: isCurrentUser
    )
  }

  var joinsPrevious: Bool {
    switch position {
    case .middle, .trailing:
      return true

    case .standalone, .leading:
      return false
    }
  }

  var joinsNext: Bool {
    switch position {
    case .leading, .middle:
      return true

    case .standalone, .trailing:
      return false
    }
  }

  var showsAvatar: Bool {
    !isCurrentUser && !joinsPrevious
  }

  var showsSenderLabel: Bool {
    !isCurrentUser && !joinsPrevious
  }

  var showsOutgoingBottomTail: Bool {
    isCurrentUser && joinsNext
  }

  var showsIncomingBottomTail: Bool {
    !isCurrentUser && joinsNext
  }
}

enum FriendsChatMessageGrouping {
  static let maximumGap: TimeInterval = 5 * 60

  static func context(
    for message: FriendMessage,
    previous: FriendMessage?,
    next: FriendMessage?,
    viewerUserId: String
  ) -> FriendsChatMessageGroupContext {
    let joinsPrevious = previous.map { shouldGroup($0, message) } ?? false
    let joinsNext = next.map { shouldGroup(message, $0) } ?? false

    let position: FriendsChatMessageGroupPosition
    switch (joinsPrevious, joinsNext) {
    case (false, false):
      position = .standalone

    case (false, true):
      position = .leading

    case (true, true):
      position = .middle

    case (true, false):
      position = .trailing
    }

    return FriendsChatMessageGroupContext(
      position: position,
      isCurrentUser: message.senderUserId == viewerUserId
    )
  }

  static func shouldGroup(_ lhs: FriendMessage, _ rhs: FriendMessage) -> Bool {
    guard lhs.senderUserId == rhs.senderUserId else { return false }
    guard lhs.messageType == .user, rhs.messageType == .user else { return false }
    guard lhs.deletedAt == nil, rhs.deletedAt == nil else { return false }
    guard lhs.shiftSnapshot == nil, rhs.shiftSnapshot == nil else { return false }
    guard canContinueGroupAfterMessage(lhs), canJoinGroupFromPreviousMessage(rhs) else {
      return false
    }

    let gap = rhs.createdAt.timeIntervalSince(lhs.createdAt)
    return gap >= 0 && gap <= maximumGap
  }

  private static func canContinueGroupAfterMessage(_ message: FriendMessage) -> Bool {
    guard message.replyToMessageId == nil else { return false }
    guard !message.attachments.isEmpty else { return true }
    return message.normalizedBody == nil
  }

  private static func canJoinGroupFromPreviousMessage(_ message: FriendMessage) -> Bool {
    message.replyToMessageId == nil && message.attachments.isEmpty
  }

  static func initials(from displayName: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }

    let components =
      trimmed
      .split(whereSeparator: \.isWhitespace)
      .prefix(2)
      .map { String($0.prefix(1)).uppercased() }

    if components.count >= 2 {
      return components.joined()
    }

    return String(trimmed.prefix(2)).uppercased()
  }
}
