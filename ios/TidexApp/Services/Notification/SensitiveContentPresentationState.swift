import Foundation

@MainActor
internal final class SensitiveContentPresentationState {
  internal enum VisibleContext: Equatable {
    case friendThread(threadId: String, ownerId: UUID)
    case sharedCalendar(ownerId: String, ownerToken: UUID)
  }

  internal static let shared: SensitiveContentPresentationState = SensitiveContentPresentationState()

  internal private(set) var visibleContext: VisibleContext?

  internal var isSensitiveContentVisible: Bool {
    visibleContext != nil
  }

  internal var activeFriendThreadId: String? {
    guard case .friendThread(let threadId, _) = visibleContext else {
      return nil
    }

    return threadId
  }

  internal var activeSharedCalendarOwnerId: String? {
    guard case .sharedCalendar(let ownerId, _) = visibleContext else {
      return nil
    }

    return ownerId
  }

  private init() {
    // Singleton.
  }

  internal func setVisibleContext(_ context: VisibleContext?) {
    visibleContext = context
  }

  internal func clearVisibleContextIfOwnedByFriendThread(_ ownerId: UUID) {
    guard case .friendThread(_, let activeOwnerId) = visibleContext,
      activeOwnerId == ownerId
    else {
      return
    }

    visibleContext = nil
  }

  internal func clearVisibleContextIfOwnedBySharedCalendar(_ ownerToken: UUID) {
    guard case .sharedCalendar(_, let activeOwnerToken) = visibleContext,
      activeOwnerToken == ownerToken
    else {
      return
    }

    visibleContext = nil
  }

  deinit {
    // Singleton.
  }
}
