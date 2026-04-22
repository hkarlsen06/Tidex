import Foundation

enum WageyChatMessageGrouping {
  static let maximumGap: TimeInterval = 5 * 60

  static func context(
    for message: ChatMessage,
    previous: ChatMessage?,
    next: ChatMessage?
  ) -> ChatMessageGroupContext {
    let joinsPrevious = previous.map { shouldGroup($0, message) } ?? false
    let joinsNext = next.map { shouldGroup(message, $0) } ?? false

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

  static func shouldGroup(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
    guard lhs.role == rhs.role else { return false }
    guard lhs.hasGroupedBubbleContent, rhs.hasGroupedBubbleContent else { return false }

    let gap = rhs.timestamp.timeIntervalSince(lhs.timestamp)
    return gap >= 0 && gap <= maximumGap
  }
}
