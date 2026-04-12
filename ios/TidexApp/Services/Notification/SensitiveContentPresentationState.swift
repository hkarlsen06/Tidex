import Foundation

@MainActor
final class SensitiveContentPresentationState {
  enum VisibleContext: Equatable {
    case friendThread(threadId: String, ownerId: UUID)
  }

  static let shared = SensitiveContentPresentationState()

  private(set) var visibleContext: VisibleContext?

  var isSensitiveContentVisible: Bool {
    visibleContext != nil
  }

  var activeFriendThreadId: String? {
    guard case .friendThread(let threadId, _) = visibleContext else { return nil }
    return threadId
  }

  private init() {}

  func setVisibleContext(_ context: VisibleContext?) {
    visibleContext = context
  }

  func clearVisibleContextIfOwnedByFriendThread(_ ownerId: UUID) {
    guard case .friendThread(_, let activeOwnerId) = visibleContext,
      activeOwnerId == ownerId
    else {
      return
    }

    visibleContext = nil
  }
}
