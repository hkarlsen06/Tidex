import Foundation

@MainActor
final class SensitiveContentPresentationState {
  enum VisibleContext: Equatable {
    case friendThread(threadId: String, ownerId: UUID)
    case sharedCalendar(ownerId: String, ownerToken: UUID)
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

  var activeSharedCalendarOwnerId: String? {
    guard case .sharedCalendar(let ownerId, _) = visibleContext else { return nil }
    return ownerId
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

  func clearVisibleContextIfOwnedBySharedCalendar(_ ownerToken: UUID) {
    guard case .sharedCalendar(_, let activeOwnerToken) = visibleContext,
      activeOwnerToken == ownerToken
    else {
      return
    }

    visibleContext = nil
  }
}
