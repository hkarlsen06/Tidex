import Foundation

enum WageyChatMessageGrouping {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static let maximumGap: TimeInterval = 5 * 60  // swiftlint:disable:this explicit_acl no_magic_numbers

  static func context(  // swiftlint:disable:this explicit_acl
    for message: ChatMessage,
    previous: ChatMessage?,
    next: ChatMessage?
  ) -> ChatMessageGroupContext {
    let joinsPrevious = previous.map { shouldGroup($0, message) } ?? false  // swiftlint:disable:this explicit_type_interface line_length
    let joinsNext = next.map { shouldGroup(message, $0) } ?? false  // swiftlint:disable:this explicit_type_interface

    let position: ChatMessageGroupPosition
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

    return ChatMessageGroupContext(
      position: position,
      isCurrentUser: message.role == .user
    )
  }

  static func shouldGroup(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {  // swiftlint:disable:this explicit_acl
    guard lhs.role == rhs.role else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    guard lhs.hasGroupedBubbleContent, rhs.hasGroupedBubbleContent else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let gap = rhs.timestamp.timeIntervalSince(lhs.timestamp)  // swiftlint:disable:this explicit_type_interface
    return gap >= 0 && gap <= maximumGap
  }
}
